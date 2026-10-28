#!/usr/bin/env bash
# Usage: bash verify-wsl.sh [--bin-dir DIR] [--gpu N] [--skip-gpu] [--playback]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/build-env.sh"
bin_dir="$ARTIFACTS_DIR"
gpu=0
skip_gpu=0
playback=0
while (($#)); do
    case "$1" in
        --bin-dir|--gpu)
            (($# >= 2)) || { echo "Missing value: $1" >&2; exit 2; }
            if [[ "$1" == --bin-dir ]]; then bin_dir="$2"; else gpu="$2"; fi
            shift 2 ;;
        --skip-gpu) skip_gpu=1; shift ;;
        --playback) playback=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ "$gpu" =~ ^[0-9]+$ ]] || { echo 'GPU must be a nonnegative integer' >&2; exit 2; }
for exe in ffmpeg ffprobe ffplay; do
    [[ -x "$bin_dir/$exe" ]] || { echo "Missing Linux executable: $bin_dir/$exe" >&2; exit 1; }
done
bin_dir="$(cd "$bin_dir" && pwd)"
ffmpeg="$bin_dir/ffmpeg"
ffprobe="$bin_dir/ffprobe"
ffplay="$bin_dir/ffplay"
test_dir="$(mktemp -d "$bin_dir/tests-XXXXXXXX")"
printf 'Test,Status\n' > "$test_dir/summary.csv"
active_test=initialization
trap 'code=$?; if ((code != 0)); then printf "%s,FAIL\n" "$active_test" >> "$test_dir/summary.csv"; fi; echo "Results: $test_dir"' EXIT
run() {
    local name="$1"; shift
    active_test="$name"
    if "$@" > "$test_dir/$name.stdout.txt" 2> "$test_dir/$name.stderr.txt"; then
        printf '%s,PASS\n' "$name" >> "$test_dir/summary.csv"
    else
        local code=$?
        tail -n 40 "$test_dir/$name.stderr.txt" >&2
        return "$code"
    fi
}
probe() {
    local path="$1" codec="$2" width="$3" height="$4" name="$5"
    run "$name" "$ffprobe" -v error -select_streams v:0 -count_frames \
        -show_entries stream=codec_name,width,height,nb_read_frames -of json "$path"
    active_test="$name-validation"
    python3 - "$test_dir/$name.stdout.txt" "$codec" "$width" "$height" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    streams = json.load(f)['streams']
assert len(streams) == 1, streams
s = streams[0]
assert (s['codec_name'], s['width'], s['height']) == (sys.argv[2], int(sys.argv[3]), int(sys.argv[4])), s
assert int(s['nb_read_frames']) > 0, s
PY
    printf '%s,PASS\n' "$active_test" >> "$test_dir/summary.csv"
}
for exe in ffmpeg ffprobe ffplay; do
    run "$exe-elf" readelf -h "$bin_dir/$exe"
    run "$exe-version" "$bin_dir/$exe" -version
done
run buildconf "$ffmpeg" -hide_banner -buildconf
run hwaccels "$ffmpeg" -hide_banner -hwaccels
run encoders "$ffmpeg" -hide_banner -encoders
run decoders "$ffmpeg" -hide_banner -decoders
run filters "$ffmpeg" -hide_banner -filters
active_test=compiled-features
for entry in 'hwaccels cuda' 'encoders h264_nvenc' 'encoders hevc_nvenc' \
    'encoders png' 'decoders png' 'filters scale_cuda' 'filters thumbnail_cuda' 'filters hwdownload'; do
    read -r listing feature <<< "$entry"
    grep -Eq "(^|[[:space:]])${feature}([[:space:]]|$)" "$test_dir/$listing.stdout.txt"
done
printf '%s,PASS\n' "$active_test" >> "$test_dir/summary.csv"
common=(-hide_banner -nostdin -v verbose -xerror -y)
run png-roundtrip "$ffmpeg" "${common[@]}" -f lavfi -i testsrc=size=128x128:rate=1 \
    -frames:v 1 -c:v png -update 1 "$test_dir/png-test.png"
probe "$test_dir/png-test.png" png 128 128 probe-png
run decode-png "$ffmpeg" "${common[@]}" -i "$test_dir/png-test.png" -f null -
if ((skip_gpu)); then
    printf 'GPU-runtime,SKIP\n' >> "$test_dir/summary.csv"
    echo 'GPU runtime tests explicitly skipped; GPU functionality is not verified.'
else
    decode=(-hwaccel cuda -hwaccel_device "$gpu" -hwaccel_output_format cuda)
    for codec in h264 hevc; do
        run "encode-$codec" "$ffmpeg" "${common[@]}" -f lavfi -i testsrc2=size=1280x720:rate=30 \
            -t 2 -c:v "${codec}_nvenc" -gpu "$gpu" "$test_dir/$codec.mp4"
        probe "$test_dir/$codec.mp4" "$codec" 1280 720 "probe-$codec"
        run "decode-$codec" "$ffmpeg" "${common[@]}" "${decode[@]}" -i "$test_dir/$codec.mp4" \
            -vf hwdownload,format=nv12 -an -f null -
    done
    run scale-cuda "$ffmpeg" "${common[@]}" "${decode[@]}" -i "$test_dir/h264.mp4" \
        -vf scale_cuda=640:360 -an -c:v hevc_nvenc -gpu "$gpu" "$test_dir/scaled.mp4"
    probe "$test_dir/scaled.mp4" hevc 640 360 probe-scaled
    run thumbnail-cuda "$ffmpeg" "${common[@]}" "${decode[@]}" -i "$test_dir/h264.mp4" \
        -vf thumbnail_cuda=30,hwdownload,format=nv12,format=rgb24 \
        -frames:v 1 -c:v png -update 1 "$test_dir/thumbnail.png"
    probe "$test_dir/thumbnail.png" png 1280 720 probe-thumbnail
fi
if ((playback)); then
    run playback-sample "$ffmpeg" "${common[@]}" \
        -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440:sample_rate=48000 \
        -t 3 -c:v ffv1 -c:a pcm_s16le "$test_dir/playback.mkv"
    echo 'Expect moving video and a quiet tone for three seconds.'
    run playback "$ffplay" -hide_banner -autoexit -volume 10 "$test_dir/playback.mkv"
    if ((!skip_gpu)); then
        run playback-hevc "$ffplay" -hide_banner -autoexit "$test_dir/scaled.mp4"
    fi
    echo 'Playback process passed; confirm picture and sound manually.'
else
    printf 'Playback,SKIP\n' >> "$test_dir/summary.csv"
fi
echo 'All requested tests passed. See summary.csv for explicit skips.'
