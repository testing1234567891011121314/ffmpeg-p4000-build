#!/usr/bin/env bash
set -euo pipefail
jobs=${1:-4}
sync_samples=${2:-yes}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || exit 2
mkdir -p /results /samples
stage=setup
finish() {
    code=$?
    trap - EXIT
    printf 'stage=%s\nexit_code=%s\n' "$stage" "$code" > /results/status.txt
    # Preserve reference comparisons, stderr and per-test reports, including failures.
    if [ -d /build/ffmpeg/tests/data ]; then
        tar -czf /results/fate-test-data.tar.gz -C /build/ffmpeg tests/data || true
    fi
    exit "$code"
}
trap finish EXIT
cd /build/ffmpeg
wine --version > /results/wine-version.txt
git rev-parse HEAD > /results/ffmpeg-commit.txt
cp config.h config_components.h ffbuild/config.mak /results/
cp -r /artifacts /results/tested-build
# This tests the build in this image, not an arbitrary existing Windows installation.
stage=wine-startup
wine ./ffmpeg.exe -version > /results/wine-ffmpeg-version.txt 2> /results/wine-startup.stderr.txt
stage=test-discovery
make -s fate-list SAMPLES=/samples TARGET_EXEC=wine > /results/fate-list.txt
test -s /results/fate-list.txt
if [ "$sync_samples" = yes ]; then
    stage=sample-download
    make fate-rsync SAMPLES=/samples 2>&1 | tee /results/sample-download.log
fi
stage=fate
# Do not regenerate expected results (GEN=1) or suppress failures.
set +e
make -k -j"$jobs" fate SAMPLES=/samples TARGET_EXEC=wine V=1 2>&1 | tee /results/fate.log
fate_exit=${PIPESTATUS[0]}
set -e
make -s fate-list-failing > /results/fate-list-failing.txt 2>&1 || true
printf '%s\n' "$fate_exit" > /results/fate-exit-code.txt
if [ "$fate_exit" -ne 0 ]; then exit "$fate_exit"; fi
stage=completed
echo 'FATE completed successfully for the enabled tests in this image.'
