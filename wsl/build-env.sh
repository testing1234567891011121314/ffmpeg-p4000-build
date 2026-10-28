#!/usr/bin/env bash
# Source this file; all writable build paths are local to the current WSL user.
export PREFIX="$HOME/.local/opt/ffmpeg"
export BUILD_DIR="$HOME/.cache/ffmpeg-build"
export ARTIFACTS_DIR="$HOME/ffmpeg-artifacts"
export CUDA_PATH="${CUDA_PATH:-/usr/local/cuda-12.6}"
export FFMPEG_REF="${FFMPEG_REF:-n9.0.1}"
export NV_HEADERS_REF="${NV_HEADERS_REF:-n13.0.19.0}"
export PATH="$CUDA_PATH/bin:$PATH"
# Retain native system pkg-config search directories for SDL dependencies.
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
unset PKG_CONFIG_LIBDIR
export JOBS="${JOBS:-4}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; return 1; }
