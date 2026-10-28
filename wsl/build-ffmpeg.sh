#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/build-env.sh"
jobs=${1:-$JOBS}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 1; }
mkdir -p "$ARTIFACTS_DIR/metadata"
cd "$BUILD_DIR/ffmpeg"
if [[ -f ffbuild/config.mak ]]; then make distclean; fi
if ! ./configure \
    --prefix="$PREFIX" \
    --arch=x86_64 --cc=gcc --cxx=g++ \
    --host-cc=gcc --pkg-config=pkg-config --pkg-config-flags=--static \
    --nvcc="$CUDA_PATH/bin/nvcc" \
    --nvccflags="-ccbin /usr/bin/g++ -gencode arch=compute_61,code=compute_61 -O2" \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib" \
    --extra-libs="-lpthread" \
    --enable-gpl --enable-version3 --enable-nonfree \
    --enable-static --disable-shared \
    --enable-cuda-nvcc --enable-nvenc --enable-nvdec \
    --enable-zlib --enable-encoder=png --enable-decoder=png \
    --enable-sdl2 --enable-ffplay \
    --disable-debug --disable-doc \
    2>&1 | tee "${ARTIFACTS_DIR}/metadata/configure.log"; then
    cat ffbuild/config.log >&2
    exit 1
fi
cp ffbuild/config.log "${ARTIFACTS_DIR}/metadata/config.log"
# Explicit feature contract: configure must not silently drop required features.
cat config.h config_components.h > "${ARTIFACTS_DIR}/metadata/config-combined.h"
for feature in SDL2 FFPLAY ZLIB PNG_ENCODER PNG_DECODER CUDA_NVCC NVENC NVDEC \
               H264_NVENC_ENCODER HEVC_NVENC_ENCODER \
               SCALE_CUDA_FILTER THUMBNAIL_CUDA_FILTER; do
    grep -Eq "^#define CONFIG_${feature} 1$" "${ARTIFACTS_DIR}/metadata/config-combined.h" || {
        echo "Required feature missing: CONFIG_${feature}" >&2
        exit 1
    }
done
make -j"$jobs" 2>&1 | tee "${ARTIFACTS_DIR}/metadata/make.log"
make install
cp "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffprobe" "$PREFIX/bin/ffplay" "${ARTIFACTS_DIR}/"

for exe in ffmpeg ffprobe ffplay; do
    file "$ARTIFACTS_DIR/$exe" | tee "$ARTIFACTS_DIR/metadata/$exe-file.txt"
    readelf -h "$ARTIFACTS_DIR/$exe" > "$ARTIFACTS_DIR/metadata/$exe-elf.txt"
    ldd "$ARTIFACTS_DIR/$exe" > "$ARTIFACTS_DIR/metadata/$exe-libraries.txt"
    if grep -q 'not found' "$ARTIFACTS_DIR/metadata/$exe-libraries.txt"; then
        echo "Missing Linux runtime library for $exe" >&2
        exit 1
    fi
    "$ARTIFACTS_DIR/$exe" -version > "$ARTIFACTS_DIR/metadata/$exe-version.txt"
done
git -C "${BUILD_DIR}/ffmpeg" rev-parse HEAD > "${ARTIFACTS_DIR}/metadata/ffmpeg-commit.txt"
git -C "${BUILD_DIR}/nv-codec-headers" rev-parse HEAD > "${ARTIFACTS_DIR}/metadata/nv-headers-commit.txt"
nvcc --version > "${ARTIFACTS_DIR}/metadata/nvcc.txt"
gcc --version > "${ARTIFACTS_DIR}/metadata/gcc.txt"
pkg-config --modversion ffnvcodec > "${ARTIFACTS_DIR}/metadata/ffnvcodec-version.txt"
pkg-config --modversion zlib > "${ARTIFACTS_DIR}/metadata/zlib-version.txt"
cp "${BUILD_DIR}/zlib-build/CMakeCache.txt" "${ARTIFACTS_DIR}/metadata/zlib-cmake-cache.txt"
sha256sum "${BUILD_DIR}/zlib.tar.gz" > "${ARTIFACTS_DIR}/metadata/zlib-source-sha256.txt"
mkdir -p "${ARTIFACTS_DIR}/licenses"
cp "${BUILD_DIR}/zlib-1.3.2/LICENSE" "${ARTIFACTS_DIR}/licenses/zlib-LICENSE.txt"
cp "${BUILD_DIR}/SDL/LICENSE.txt" "${ARTIFACTS_DIR}/licenses/SDL2-LICENSE.txt"
git -C "${BUILD_DIR}/SDL" rev-parse HEAD > "${ARTIFACTS_DIR}/metadata/sdl2-commit.txt"
pkg-config --modversion sdl2 > "${ARTIFACTS_DIR}/metadata/sdl2-version.txt"
pkg-config --static --libs sdl2 > "${ARTIFACTS_DIR}/metadata/sdl2-static-libs.txt"
cp "${BUILD_DIR}/sdl-build/CMakeCache.txt" "${ARTIFACTS_DIR}/metadata/sdl2-cmake-cache.txt"
dpkg-query -W > "${ARTIFACTS_DIR}/metadata/packages.txt"
cp config.h ffbuild/config.mak "${ARTIFACTS_DIR}/metadata/"
cd "$ARTIFACTS_DIR"
sha256sum ffmpeg ffprobe ffplay > SHA256SUMS.txt
