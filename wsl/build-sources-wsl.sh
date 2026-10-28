#!/usr/bin/env bash
# WSL equivalent of the Dockerfile's RUN layers that fetch and build zlib,
# nv-codec-headers, FFmpeg sources, and SDL2. Run after setup-wsl-toolchain.sh
# and before build-ffmpeg.sh. Dependency caches include required metadata.
# --clean clears this user's dedicated source, install, and output directories.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/build-env.sh"

if [[ "${1:-}" == "--clean" ]]; then
    for dir in "$BUILD_DIR" "$PREFIX" "$ARTIFACTS_DIR"; do
        [[ ! -L "$dir" ]] || { echo "Refusing symlink: $dir" >&2; exit 1; }
        mkdir -p "$dir"
        find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    done
fi
mkdir -p "$BUILD_DIR" "$PREFIX" "$ARTIFACTS_DIR"
cd "$BUILD_DIR"

# --- zlib 1.3.2 (static, native Linux target) -----------------------------------
if [[ ! -s "$PREFIX/lib/libz.a" || "$(pkg-config --modversion zlib 2>/dev/null || true)" != 1.3.2 ||
      ! -f zlib-build/CMakeCache.txt || ! -f zlib.tar.gz || ! -f zlib-1.3.2/LICENSE ]]; then
    wget --https-only --timeout=30 --tries=3 -O zlib.tar.gz \
        https://zlib.net/fossils/zlib-1.3.2.tar.gz
    echo 'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16  zlib.tar.gz' | sha256sum -c -
    rm -rf zlib-1.3.2
    tar -xzf zlib.tar.gz
    rm -rf zlib-build
    cmake -S zlib-1.3.2 -B zlib-build \
        -DCMAKE_C_COMPILER=/usr/bin/gcc \
        -DCMAKE_AR=/usr/bin/ar \
        -DCMAKE_RANLIB=/usr/bin/ranlib \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON \
        -DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_MINIZIP=OFF \
        -DZLIB_INSTALL=ON
    cmake --build zlib-build --parallel "$JOBS"
    cmake --install zlib-build
    if [[ ! -f "$PREFIX/lib/libz.a" ]]; then
        cp "$PREFIX/lib/libzs.a" "$PREFIX/lib/libz.a"
    fi
    test -s "$PREFIX/lib/libz.a"
    test "$(pkg-config --modversion zlib)" = '1.3.2'
else
    echo "zlib 1.3.2 already built at $PREFIX."
fi

printf '%s\n' '#include <zlib.h>' \
    'int main(void) { return zlibVersion()[0] == 0; }' > zlib-link-test.c
gcc \
    $(pkg-config --cflags zlib) zlib-link-test.c \
    $(pkg-config --static --libs zlib) -o zlib-link-test
./zlib-link-test

# --- nv-codec-headers --------------------------------------------------------
if [[ "$(pkg-config --modversion ffnvcodec 2>/dev/null || true)" != "${NV_HEADERS_REF#n}" ||
      ! -d nv-codec-headers/.git ]]; then
    rm -rf nv-codec-headers
    git init nv-codec-headers
    git -C nv-codec-headers remote add origin https://github.com/FFmpeg/nv-codec-headers.git
    git -C nv-codec-headers fetch --depth 1 origin "${NV_HEADERS_REF}"
    git -C nv-codec-headers checkout --detach FETCH_HEAD
    make -C nv-codec-headers install PREFIX="$PREFIX"
fi
test "$(pkg-config --modversion ffnvcodec)" = "${NV_HEADERS_REF#n}"

# --- FFmpeg source ------------------------------------------------------------
if [[ ! -d ffmpeg/.git ]]; then
    git init ffmpeg
    git -C ffmpeg remote add origin https://github.com/FFmpeg/FFmpeg.git
fi
git -C ffmpeg fetch --depth 1 origin "${FFMPEG_REF}"
if [[ -f ffmpeg/ffbuild/config.mak ]]; then make -C ffmpeg distclean; fi
git -C ffmpeg checkout --detach FETCH_HEAD

# --- SDL2 2.32.10, pinned commit --------------------------------------------
SDL_COMMIT=5d249570393f7a37e037abf22cd6012a4cc56a71
if [[ "$(pkg-config --modversion sdl2 2>/dev/null || true)" != '2.32.10' ||
      ! -s "$PREFIX/lib/libSDL2.a" || ! -d SDL/.git ||
      ! -f SDL/LICENSE.txt || ! -f sdl-build/CMakeCache.txt ]]; then
    rm -rf SDL sdl-build
    git init SDL
    git -C SDL remote add origin https://github.com/libsdl-org/SDL.git
    git -C SDL fetch --depth 1 origin "$SDL_COMMIT"
    git -C SDL checkout --detach FETCH_HEAD
    test "$(git -C SDL rev-parse HEAD)" = "$SDL_COMMIT"
    cmake -S SDL -B sdl-build \
        -DCMAKE_C_COMPILER=/usr/bin/gcc \
        -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
        -DCMAKE_AR=/usr/bin/ar \
        -DCMAKE_RANLIB=/usr/bin/ranlib \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DSDL_SHARED=OFF -DSDL_STATIC=ON \
        -DSDL_TEST=OFF -DSDL_TESTS=OFF
    cmake --build sdl-build --parallel "$JOBS"
    cmake --install sdl-build
else
    echo "SDL2 2.32.10 already built at $PREFIX."
fi
test "$(pkg-config --modversion sdl2)" = '2.32.10'

printf '%s\n' '#include <SDL.h>' \
    'int main(int argc, char **argv) { (void)argc; (void)argv; return SDL_Init(0); }' > sdl-link-test.c
gcc \
    $(pkg-config --cflags sdl2) sdl-link-test.c \
    $(pkg-config --static --libs sdl2) -o sdl-link-test
./sdl-link-test

echo "Sources and dependencies ready under $BUILD_DIR."
