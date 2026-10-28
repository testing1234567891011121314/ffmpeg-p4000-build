#!/usr/bin/env bash
set -euo pipefail
jobs=${1:-4}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 1; }
mkdir -p /artifacts/metadata
cd /build/ffmpeg
if ! ./configure \
    --prefix="$PREFIX" \
    --arch=x86_64 --target-os=mingw32 --enable-cross-compile \
    --cross-prefix=x86_64-w64-mingw32- \
    --cc=x86_64-w64-mingw32-gcc-posix \
    --cxx=x86_64-w64-mingw32-g++-posix \
    --host-cc=gcc --pkg-config=pkg-config --pkg-config-flags=--static \
    --nvcc="$CUDA_PATH/bin/nvcc" \
    --nvccflags="-ccbin /usr/bin/g++ -gencode arch=compute_61,code=compute_61 -O2" \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib -static -static-libgcc" \
    --extra-libs="-lpthread" \
    --enable-gpl --enable-version3 --enable-nonfree \
    --enable-static --disable-shared \
    --enable-cuda-nvcc --enable-nvenc --enable-nvdec \
    --enable-zlib --enable-encoder=png --enable-decoder=png \
    --enable-sdl2 --enable-ffplay \
    --disable-debug --disable-doc \
    2>&1 | tee /artifacts/metadata/configure.log; then
    cat ffbuild/config.log >&2
    exit 1
fi
cp ffbuild/config.log /artifacts/metadata/config.log
# Explicit feature contract: configure must not silently drop required features.
cat config.h config_components.h > /artifacts/metadata/config-combined.h
for feature in SDL2 FFPLAY ZLIB PNG_ENCODER PNG_DECODER CUDA_NVCC NVENC NVDEC \
               H264_NVENC_ENCODER HEVC_NVENC_ENCODER \
               SCALE_CUDA_FILTER THUMBNAIL_CUDA_FILTER; do
    grep -Eq "^#define CONFIG_${feature} 1$" /artifacts/metadata/config-combined.h || {
        echo "Required feature missing: CONFIG_${feature}" >&2
        exit 1
    }
done
make -j"$jobs" 2>&1 | tee /artifacts/metadata/make.log
make install
cp "$PREFIX/bin/ffmpeg.exe" "$PREFIX/bin/ffprobe.exe" "$PREFIX/bin/ffplay.exe" /artifacts/

for exe in ffmpeg ffprobe ffplay; do
    file "/artifacts/$exe.exe" | tee "/artifacts/metadata/$exe-file.txt"
    x86_64-w64-mingw32-objdump -p "/artifacts/$exe.exe" > "/artifacts/metadata/$exe-pe.txt"
    # Assert that MinGW runtime DLLs were not left as external dependencies.
    if grep -Ei 'DLL Name:.*(libwinpthread|libgcc_s|libstdc\+\+|zlib|libz[.-]|SDL2)' "/artifacts/metadata/$exe-pe.txt"; then
        echo "Unexpected compiler-runtime, zlib or SDL2 DLL dependency in $exe" >&2
        exit 1
    fi
done
git -C /build/ffmpeg rev-parse HEAD > /artifacts/metadata/ffmpeg-commit.txt
git -C /build/nv-codec-headers rev-parse HEAD > /artifacts/metadata/nv-headers-commit.txt
nvcc --version > /artifacts/metadata/nvcc.txt
x86_64-w64-mingw32-gcc-posix --version > /artifacts/metadata/mingw.txt
pkg-config --modversion ffnvcodec > /artifacts/metadata/ffnvcodec-version.txt
pkg-config --modversion zlib > /artifacts/metadata/zlib-version.txt
cp /build/zlib-build/CMakeCache.txt /artifacts/metadata/zlib-cmake-cache.txt
sha256sum /build/zlib.tar.gz > /artifacts/metadata/zlib-source-sha256.txt
mkdir -p /artifacts/licenses
cp /build/zlib-1.3.2/LICENSE /artifacts/licenses/zlib-LICENSE.txt
cp /build/SDL/LICENSE.txt /artifacts/licenses/SDL2-LICENSE.txt
git -C /build/SDL rev-parse HEAD > /artifacts/metadata/sdl2-commit.txt
pkg-config --modversion sdl2 > /artifacts/metadata/sdl2-version.txt
pkg-config --static --libs sdl2 > /artifacts/metadata/sdl2-static-libs.txt
cp /build/sdl-build/CMakeCache.txt /artifacts/metadata/sdl2-cmake-cache.txt
dpkg-query -W > /artifacts/metadata/packages.txt
cp config.h ffbuild/config.mak /artifacts/metadata/
cd /artifacts
sha256sum ffmpeg.exe ffprobe.exe ffplay.exe > SHA256SUMS.txt
