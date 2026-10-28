Native Linux FFmpeg for WSL2
===========================
This recipe builds x86_64 Linux ELF executables, not Windows .exe files.
Supported build environment: Ubuntu 22.04 x86_64 inside WSL2.

User-local paths (defined once in build-env.sh):
  Install:  $HOME/.local/opt/ffmpeg
  Sources:  $HOME/.cache/ffmpeg-build
  Outputs:  $HOME/ffmpeg-artifacts
These paths use the WSL user's HOME. There is no system-wide /opt install,
/build directory, /artifacts directory, or recursive sudo chown.
Only apt/CUDA package provisioning needs sudo. CUDA itself remains a system
package at /usr/local/cuda-12.6; it is not the FFmpeg install prefix.

Files
-----
Keep all scripts together, including the new build-env.sh and verify-wsl.sh.
Keep shell files in LF format. Do not run the entire build with sudo.

From PowerShell:
  .\build-wsl.ps1 -Distro Ubuntu-22.04 -Jobs 4
  .\verify.ps1 -Distro Ubuntu-22.04

From inside WSL, in the script folder:
  bash run-build-wsl.sh 4
  bash verify-wsl.sh

The PowerShell builder copies Linux executables and metadata to a fresh
out-<timestamp>-<id> directory for convenience. They remain Linux programs.
The default verification uses the original WSL output directory. To test
another directory, use verify.ps1 -BinDir <Windows-or-Linux-path> or
bash verify-wsl.sh --bin-dir /linux/path.

Clean builds
------------
  .\build-wsl.ps1 -Distro Ubuntu-22.04 -Clean
  bash run-build-wsl.sh 4 --clean
--clean deletes all contents of the three dedicated user-local paths above,
including previous test logs, but preserves the directories themselves.
Do not keep unrelated files in those paths. Dependency cache checks also
rebuild when required source/metadata files are missing. FFmpeg objects are
cleaned before reconfiguration, including when the source revision changes.
Jobs applies to the zlib, SDL2, and FFmpeg builds.

Verification
------------
The default suite checks Linux executable startup, compiled features, PNG,
H.264/HEVC NVENC, CUDA hardware decoding, scale_cuda, and thumbnail_cuda.
It records stdout/stderr per command and summary.csv in a tests-* directory.
A failed test stops the suite; later tests are not claimed to have passed.

  bash verify-wsl.sh --gpu 0 --playback
  .\verify.ps1 -Distro Ubuntu-22.04 -Gpu 0 -Playback
Playback requires a working WSL graphical/audio session. Confirm picture
and sound manually; successful process exit alone does not establish either.
--skip-gpu / -SkipGpu explicitly skips GPU runtime tests; it does not waive
the requirement that the binary contain the requested compiled GPU features.

Dependencies and scope
----------------------
The original pinned FFmpeg/header refs, zlib hash/version, SDL2 commit, and
CUDA 12.6 package choice are retained. Override refs with -FFmpegRef and
-HeadersRef in PowerShell, or FFMPEG_REF and NV_HEADERS_REF in Bash. Fetch or
hash errors are fatal; the scripts do not silently substitute another source.
Source availability and a full build have not been validated in the editing
environment. GPU functionality must be checked on the target WSL machine.

FFmpeg, zlib, and SDL2 are built as static libraries, but the executables can
use Linux system shared libraries. They are not fully static portable binaries.
The build records ldd output and fails if a linked library is missing.
The native pkg-config system search path stays available for SDL dependencies.

Setup installs toolkit components only, not an NVIDIA Linux display driver.
Runtime GPU tests require a working WSL GPU configuration and compatible GPU
and driver. CUDA_PATH can override the compiler location; setup still provisions
the pinned CUDA 12.6 packages. Concurrent builds by the same WSL user are not
supported because they share the dedicated build and install directories.

Validation performed during editing
-----------------------------------
All six Bash scripts pass bash -n. Isolated temporary-directory tests passed
for clean deletion (including hidden files and paths with spaces), symlink
refusal, and verifier failure/skip reporting using mocked executables.
PowerShell execution, actual compilation, GPU runtime, and WSLg playback
were not run in the editing environment.
