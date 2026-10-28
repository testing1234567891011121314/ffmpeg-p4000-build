# syntax=docker/dockerfile:1
# Version-selected build; apt packages and base image are not byte-for-byte locked.
FROM ubuntu:22.04 AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ARG FFMPEG_REF=n9.0.1
ARG NV_HEADERS_REF=n13.0.19.0
ARG JOBS=4

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config nasm yasm git wget ca-certificates gnupg \
    gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix \
    binutils-mingw-w64-x86-64 file \
 && rm -rf /var/lib/apt/lists/*

# Linux NVCC produces embedded PTX; MinGW produces the Windows executable.
# CUDA 12.6 is a deliberate choice for Pascal, not a host-toolkit dependency.
RUN wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
 && dpkg -i cuda-keyring_1.1-1_all.deb \
 && rm cuda-keyring_1.1-1_all.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends cuda-nvcc-12-6 cuda-cudart-dev-12-6 \
 && rm -rf /var/lib/apt/lists/*

ENV CUDA_PATH=/usr/local/cuda-12.6
ENV PATH=/usr/local/cuda-12.6/bin:$PATH
ENV PREFIX=/opt/win64
ENV PKG_CONFIG_PATH=/opt/win64/lib/pkgconfig
ENV PKG_CONFIG_LIBDIR=/opt/win64/lib/pkgconfig
WORKDIR /build

# Upstream zlib 1.3.2 tar.gz checksum, published at https://zlib.net/.
# Build Windows libraries: Ubuntu's zlib1g-dev contains Linux libraries.
RUN wget --https-only --timeout=30 --tries=3 -O zlib.tar.gz \
      https://zlib.net/fossils/zlib-1.3.2.tar.gz \
 && echo 'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16  zlib.tar.gz' | sha256sum -c - \
 && tar -xzf zlib.tar.gz \
 && cmake -S zlib-1.3.2 -B zlib-build \
      -DCMAKE_SYSTEM_NAME=Windows \
      -DCMAKE_C_COMPILER=/usr/bin/x86_64-w64-mingw32-gcc-posix \
      -DCMAKE_RC_COMPILER=/usr/bin/x86_64-w64-mingw32-windres \
      -DCMAKE_AR=/usr/bin/x86_64-w64-mingw32-ar \
      -DCMAKE_RANLIB=/usr/bin/x86_64-w64-mingw32-ranlib \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/win64 \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON \
      -DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_MINIZIP=OFF \
      -DZLIB_INSTALL=ON \
 && cmake --build zlib-build --parallel 4 \
 && cmake --install zlib-build \
 && if [ ! -f "$PREFIX/lib/libz.a" ]; then \
      cp "$PREFIX/lib/libzs.a" "$PREFIX/lib/libz.a"; \
    fi \
 && test -s "$PREFIX/lib/libz.a" \
 && test "$(pkg-config --modversion zlib)" = '1.3.2'

# CMake may name the Windows static library libzs.a; libz.a above supplies
# FFmpeg's conventional -lz fallback. Verify target linking, not just headers.
RUN printf '%s\n' '#include <zlib.h>' \
      'int main(void) { return zlibVersion()[0] == 0; }' > zlib-link-test.c \
 && x86_64-w64-mingw32-gcc-posix -static \
      $(pkg-config --cflags zlib) zlib-link-test.c \
      $(pkg-config --static --libs zlib) -o zlib-link-test.exe \
 && x86_64-w64-mingw32-objdump -f zlib-link-test.exe | grep -q 'pei-x86-64'

# fetch accepts a release tag or a reachable commit SHA; resolved SHAs are exported.
RUN git init nv-codec-headers \
 && git -C nv-codec-headers remote add origin https://github.com/FFmpeg/nv-codec-headers.git \
 && git -C nv-codec-headers fetch --depth 1 origin "${NV_HEADERS_REF}" \
 && git -C nv-codec-headers checkout --detach FETCH_HEAD \
 && make -C nv-codec-headers install PREFIX="$PREFIX" \
 && test "$(pkg-config --modversion ffnvcodec)" = "13.0.19.0"

RUN git init ffmpeg \
 && git -C ffmpeg remote add origin https://github.com/FFmpeg/FFmpeg.git \
 && git -C ffmpeg fetch --depth 1 origin "${FFMPEG_REF}" \
 && git -C ffmpeg checkout --detach FETCH_HEAD

# SDL2 2.32.10, pinned to the upstream release commit. FFplay uses SDL2,
# not SDL3. Static linking keeps SDL2.dll out of the installation.
RUN git init SDL \
 && git -C SDL remote add origin https://github.com/libsdl-org/SDL.git \
 && git -C SDL fetch --depth 1 origin 5d249570393f7a37e037abf22cd6012a4cc56a71 \
 && git -C SDL checkout --detach FETCH_HEAD \
 && test "$(git -C SDL rev-parse HEAD)" = 5d249570393f7a37e037abf22cd6012a4cc56a71 \
 && for tool in gcc-posix g++-posix windres ar ranlib; do \
      test -x "/usr/bin/x86_64-w64-mingw32-$tool" || exit 1; \
    done \
 && cmake -S SDL -B sdl-build \
      -DCMAKE_SYSTEM_NAME=Windows \
      -DCMAKE_C_COMPILER=/usr/bin/x86_64-w64-mingw32-gcc-posix \
      -DCMAKE_CXX_COMPILER=/usr/bin/x86_64-w64-mingw32-g++-posix \
      -DCMAKE_RC_COMPILER=/usr/bin/x86_64-w64-mingw32-windres \
      -DCMAKE_AR=/usr/bin/x86_64-w64-mingw32-ar \
      -DCMAKE_RANLIB=/usr/bin/x86_64-w64-mingw32-ranlib \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/win64 \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DSDL_SHARED=OFF -DSDL_STATIC=ON \
      -DSDL_TEST=OFF -DSDL_TESTS=OFF \
 && cmake --build sdl-build --parallel 4 \
 && cmake --install sdl-build \
 && test "$(pkg-config --modversion sdl2)" = '2.32.10'

# Verify Windows SDL linking, including its private/static dependencies.
RUN printf '%s\n' '#include <SDL.h>' \
      'int main(int argc, char **argv) { (void)argc; (void)argv; return SDL_Init(0); }' > sdl-link-test.c \
 && x86_64-w64-mingw32-gcc-posix -static \
      $(pkg-config --cflags sdl2) sdl-link-test.c \
      $(pkg-config --static --libs sdl2) -o sdl-link-test.exe \
 && x86_64-w64-mingw32-objdump -f sdl-link-test.exe | grep -q 'pei-x86-64'

COPY build-ffmpeg.sh /build/build-ffmpeg.sh
RUN bash /build/build-ffmpeg.sh "${JOBS}"

# Export only deliverables, with no temporary container or stale-image copy step.
FROM scratch AS artifacts
COPY --from=build /artifacts/ /
