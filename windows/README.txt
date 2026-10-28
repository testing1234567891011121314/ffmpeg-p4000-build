FFmpeg for Windows x64 / Quadro P4000
====================================

This package selects FFmpeg n9.0.1, nv-codec-headers n13.0.19.0, and
Linux CUDA 12.6 for compute_61 PTX, checksum-verified static zlib 1.3.2,
and static SDL2 2.32.10 pinned to its upstream release commit. NVCC runs with the Linux compiler;
MinGW compiles the Windows executable. No host CUDA toolkit or GPU is
needed to build. A compatible NVIDIA driver and P4000 are needed to test.

Prerequisites: Docker Desktop running Linux containers, Docker buildx,
Windows PowerShell 5.1 or newer, and access to Ubuntu/NVIDIA package
repositories and GitHub. Docker Desktop requires a Linux VM backend
(WSL2 or Hyper-V on supported Windows editions); no manual WSL shell is
needed. The build explicitly targets linux/amd64.

From PowerShell in this extracted directory:

  .\build.ps1

If local policy blocks a downloaded script, review the files and use a
process-only invocation where your organization permits it:

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1

Optional clean rebuild with lower memory demand:

  .\build.ps1 -NoCache -Jobs 2

The script prints a new out-<timestamp>-<id> directory. On the P4000
Windows computer, run (substitute the actual directory):

  .\verify.ps1 -BinDir .\out-<timestamp>-<id>

Tests assert compiled CUDA/NVENC/filter and PNG encoder/decoder support,
perform standalone PNG encoding/decoding, and exercise H.264/HEVC
NVENC, H.264/HEVC NVDEC, scale_cuda, and thumbnail_cuda. Output codec,
dimensions and readable frames are checked with ffprobe. A summary.csv
and per-command stdout/stderr logs are saved even if a test fails. Tests
stop at the first failure; subsequent tests are not run.
On systems with multiple NVIDIA GPUs, select the P4000 CUDA device:

  .\verify.ps1 -BinDir .\out-<timestamp>-<id> -Gpu 1

Tests cover 8-bit H.264/HEVC; other listed codecs/filters are not tested.
Inspect the output videos and thumbnail. Keep GPU/driver information
alongside the exported build metadata.

Equivalent direct build command (use a NEW output directory each time):

  docker buildx build --platform linux/amd64 --progress plain --target artifacts --build-arg JOBS=4 --output type=local,dest=./out-manual .
  if ($LASTEXITCODE -ne 0) { throw 'Docker build failed' }

The final scratch stage is an export target, not a runnable image.
For an interactive builder image instead:

  docker buildx build --platform linux/amd64 --target build --load -t ffmpeg-p4000-builder .
  if ($LASTEXITCODE -ne 0) { throw 'Docker build failed' }
  docker run --rm -it ffmpeg-p4000-builder bash

The builder cannot directly run the Windows executables. Build failures
must be fixed before export/testing. Configure failure prints config.log.
For successful builds, metadata contains configure/build logs, package
versions, source commits, compiler versions and PE imports. SHA256SUMS.txt
records hashes of all three executables (ffmpeg, ffprobe, ffplay). No MinGW runtime DLL dependency
is permitted by the build check; Windows/NVIDIA driver DLLs are still needed.

Scope and limitations
---------------------
- The preceding recipe passed PNG encoding/decoding, H.264/HEVC NVENC/
  NVDEC, scale_cuda and thumbnail_cuda tests on two P4000 GPUs with
  Windows driver 582.78 (user-supplied logs). The newly added SDL2/ffplay
  build has NOT been compiled or runtime-tested here. Rebuild and run all
  tests, including interactive playback, before accepting this revision.
- This is a focused P4000 build, not feature-equivalent to a full Gyan build.
  For production release, retain the tested executables and checksums, pin
  all source commits, base-image digest and package snapshots, and validate
  representative workloads beyond the short feature smoke tests.
- Version-selected, NOT byte-for-byte reproducible: base image and apt package
  revisions can change. For stricter reproduction lock the base digest, use
  retained package snapshots, and pass the recorded commit SHAs as FFmpegRef
  and HeadersRef. The header package version is checked as 13.0.19.0.
- No host CUDA detection is needed. CUDA 12.6 is selected; it is not the only
  toolkit that can target Pascal. CUDA 13 cannot compile compute_61.
- No libx264/libx265 or NPP are included. CPU x264/x265 fallback needs
  a separate build that includes those libraries. MX130 is not the target.
- --enable-nonfree is used for this CUDA-NVCC configuration. FFmpeg labels
  such builds nonredistributable; this package is a local build recipe.
- GPU hardware/codec capabilities and driver support still constrain use.
  An encoder/filter listing alone is not proof of runtime support.

References
----------
https://docs.nvidia.com/cuda/archive/12.6.3/cuda-toolkit-release-notes/index.html
https://docs.nvidia.com/deploy/cuda-compatibility/minor-version-compatibility.html
https://ffmpeg.org/ffmpeg-filters.html

PNG fix and upstream alignment
------------------------------
The Dockerfile now builds Windows static zlib with upstream CMake options,
checks the official source SHA-256, and links a Windows smoke-test executable
against it. It does not use Ubuntu's Linux zlib development libraries.
FFmpeg explicitly enables zlib and PNG encoding/decoding. Generated config
macros must show every required PNG/CUDA/NVENC feature or the build fails.
Final imports must not include zlib or MinGW runtime DLLs.
The verification script retains PNG output; it does not hide missing PNG
support behind a BMP fallback.

Rebuild using the updated Dockerfile, build-ffmpeg.sh and verify.ps1:

  .\build.ps1
  .\verify.ps1 -BinDir .\out-<new-directory> -Gpu 0
  .\verify.ps1 -BinDir .\out-<new-directory> -Gpu 1

Docker invalidates the changed dependency/build layers automatically. A
full --no-cache rebuild is optional. Keep using the chosen FFmpeg revision
(or pass its recorded commit SHA) to avoid unrelated source changes.

https://ffmpeg.org/platform.html#Cross-compilation-for-Windows-with-Linux
https://github.com/madler/zlib/blob/develop/README-cmake.md
https://zlib.net/

FFplay and viewing recordings
-----------------------------
The build now exports ffmpeg.exe, ffprobe.exe and ffplay.exe. SDL2 and
zlib are static; the build rejects direct SDL2, zlib and MinGW runtime
DLL dependencies in all three executables. Windows system DLLs and
NVIDIA driver DLLs are still required and supplied by their installers.
Do not add DLL files from another FFmpeg distribution.

The normal verification includes ffplay -version (startup only). On an
interactive Windows desktop, also run:

  .\verify.ps1 -BinDir .\out-<new-directory> -Gpu 0 -Playback

Playback opens a 3-second H.264 clip with a quiet tone, followed by a
2-second HEVC clip. Observe the picture and sound yourself; zero process
exit status does not establish that they appeared correctly. Playback
uses ffplay's normal decoding/rendering path, not a CUDA decode test.
The separate FFmpeg tests continue to verify CUDA/NVDEC explicitly.

After successful tests, copy all THREE executables into:

  C:\Tools\ffmpeg\bin

Once that directory is on PATH, view a recording with:

  ffplay -autoexit "D:\Recordings\recording.mp4"

Space pauses/resumes; f toggles fullscreen; q or Escape closes playback.

Upstream SDL2 CMake instructions:
https://wiki.libsdl.org/SDL2/README-cmake
SDL2 release commit:
https://github.com/libsdl-org/SDL/commit/5d249570393f7a37e037abf22cd6012a4cc56a71
