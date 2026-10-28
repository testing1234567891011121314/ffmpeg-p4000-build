#!/usr/bin/env bash
# Usage: bash run-build-wsl.sh [JOBS] [--clean]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
JOBS=4
clean_args=()
for arg in "$@"; do
    if [[ "$arg" == --clean ]]; then clean_args=(--clean); else JOBS="$arg"; fi
done
export JOBS
source ./build-env.sh
bash ./setup-wsl-toolchain.sh
bash ./build-sources-wsl.sh "${clean_args[@]}"
bash ./build-ffmpeg.sh "$JOBS"
echo "Done. Linux executables: $ARTIFACTS_DIR"
echo "Verify: bash verify-wsl.sh --bin-dir \"$ARTIFACTS_DIR\""
