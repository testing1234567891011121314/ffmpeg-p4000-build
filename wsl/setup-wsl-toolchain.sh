#!/usr/bin/env bash
# One-time provisioning for an Ubuntu 22.04 WSL2 distro, replacing the
# Dockerfile's "FROM ubuntu:22.04" + first two RUN layers (apt packages,
# CUDA keyring/nvcc). Safe to re-run; already-installed pieces are skipped.
#
# Usage (inside WSL):  bash setup-wsl-toolchain.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/build-env.sh"
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 && "$(uname -m)" == x86_64 ]] || {
    echo "This recipe requires x86_64 Ubuntu 22.04 (CUDA repository is pinned)." >&2
    exit 1
}
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential binutils cmake pkg-config nasm yasm git wget ca-certificates gnupg \
    file lsb-release python3 libx11-dev libxext-dev libxrandr-dev libxcursor-dev \
    libxi-dev libxfixes-dev libxss-dev libxinerama-dev libxkbcommon-dev \
    libwayland-dev wayland-protocols libasound2-dev libpulse-dev libudev-dev \
    libdbus-1-dev libegl1-mesa-dev libgl1-mesa-dev

if ! dpkg -s cuda-nvcc-12-6 >/dev/null 2>&1 || ! dpkg -s cuda-cudart-dev-12-6 >/dev/null 2>&1; then
    tmp_deb="$(mktemp --suffix=.deb)"
    wget -q --https-only --timeout=30 --tries=3 -O "$tmp_deb" \
        https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i "$tmp_deb"
    rm -f "$tmp_deb"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends cuda-nvcc-12-6 cuda-cudart-dev-12-6
else
    echo "cuda-nvcc-12-6 / cuda-cudart-dev-12-6 already installed."
fi

mkdir -p "$BUILD_DIR" "$ARTIFACTS_DIR" "$PREFIX"
echo "Native Linux toolchain ready; install prefix: $PREFIX"
