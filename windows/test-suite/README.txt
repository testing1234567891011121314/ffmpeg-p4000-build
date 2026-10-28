FFmpeg regression checks (separate from verify.ps1)
=================================================

These scripts are additional checks, not a guarantee against every defect.
They have not been executed under Windows/PowerShell or Docker/Wine in the
authoring environment. Shell syntax and package integrity were checked.
Keep your existing verify.ps1 for actual Windows GPU and playback tests.

1. Compare the existing Windows executables on real recordings
------------------------------------------------------------
Run verify-regression.ps1 with the built output directory, a different
trusted FFmpeg executable, and representative recording files:

  .\verify-regression.ps1 -BinDir 'C:\Tools\ffmpeg\bin' -ReferenceFFmpeg 'C:\Tools\ffmpeg-reference\bin\ffmpeg.exe' -Inputs 'D:\Recordings\recording.mp4'

For several recordings (PowerShell array syntax):

  .\verify-regression.ps1 -BinDir 'C:\Tools\ffmpeg\bin' -ReferenceFFmpeg 'C:\Tools\ffmpeg-reference\bin\ffmpeg.exe' -Inputs @('D:\Recordings\h264.mp4','D:\Recordings\hevc.mp4')

All inputs are decoded completely four times, so long recordings take time.
Outputs are per-frame SHA-256 records, not large raw-video files. The first
video stream is tested. Its probed pixel format is retained. No scaling or
GPU decoding is requested. The script compares ordered frame sizes/hashes:
  - candidate versus reference, both using one decoder thread;
  - candidate versus the same build with -cpuflags 0;
  - candidate single-threaded versus multithreaded decoding.

The CPU-flags comparison disables runtime-dispatched optimizations, not
every intrinsic or compiler-generated SIMD instruction. It cannot prove the
reported _mm_store_si128 warning harmless. A mismatch warrants investigation;
different decoder versions can have legitimate fixes or rounding changes.
Do not automatically change the reference to make mismatches disappear.
Matching hashes also do not prove memory safety. Audio and timestamp equality
are not checked; timestamps remain in framehash files for manual inspection.
The summary marks failed cases and continues with other inputs, then throws
if any case failed. Executable hashes, commands and stderr are recorded.

2. Run upstream FATE in Docker with Wine
--------------------------------------
Requirements: Docker Desktop in Linux-container mode, enough disk space for
the FATE sample collection, and network access to package repositories and
the upstream rsync sample server (rsync access may be blocked by firewalls).
This can download substantial data and run for a long time. Samples persist
in a dedicated Docker volume for reuse. No results are uploaded to FFmpeg.

BuildDir points to the FFmpeg recipe directory, NOT the executable directory:

  .\verify-fate.ps1 -BuildDir 'D:\Users\Hejun\Documents\GitHub\ffmpeg-p4000-build' -Jobs 4

The script builds/loads the recipe's 'build' stage, adds Wine and rsync in a
separate test image, downloads samples and executes upstream 'make fate'.
It uses TARGET_EXEC=wine to run the Windows test executables. The test list
depends on the configured features. Missing samples/setup failures are errors,
not passes. Detailed reports are saved even when FATE fails. No GEN=1 is used.

If you deliberately retained a specific builder image, reuse it:

  .\verify-fate.ps1 -BuildDir 'D:\Users\Hejun\Documents\GitHub\ffmpeg-p4000-build' -BuilderImage ffmpeg-p4000-builder -ReuseBuilderImage

Use -SkipSampleSync only when that volume already has the required samples.
It does not skip missing-sample test failures.

IMPORTANT: FATE tests the build INSIDE THIS BUILDER IMAGE. A fresh rebuild is
not necessarily byte-identical to your previously installed executables.
Results include tested-build/ with its binaries, metadata and SHA256SUMS.txt.
Compare those hashes before attributing FATE results to an existing install.
The recipe still uses --enable-nonfree: do not publish its compiled binaries.

Results include status.txt (last stage and exit status), fate.log,
fate-list.txt, fate-list-failing.txt, fate-test-data.tar.gz, source commit,
configuration, image metadata and tested-build/. If sample download or Wine
startup fails, FATE itself has not run. Wine failures can be environment issues
and require investigation rather than automatically being treated as codec bugs.

FATE's default is software decoding. This harness does not certify NVIDIA
driver behavior, GUI rendering/audio, concurrent production load, or every
codec/profile. Re-run the original verify.ps1 -Playback on the P4000 Windows
machine for the tested binaries and inspect real playback.

Cleanup: the script prints its test image name; remove it with docker image rm
when no longer needed. Remove the sample volume only when you no longer need
its downloaded samples: docker volume rm ffmpeg-fate-samples

Official documentation:
https://ffmpeg.org/fate.html
https://ffmpeg.org/ffmpeg-formats.html#framehash

Useful upstream commands (already performed by verify-fate.ps1):
make fate-rsync SAMPLES=/samples
make fate-list SAMPLES=/samples TARGET_EXEC=wine
make -k -j4 fate SAMPLES=/samples TARGET_EXEC=wine V=1
make fate-list-failing
