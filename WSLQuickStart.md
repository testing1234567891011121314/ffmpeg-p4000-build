## FFmpeg quickstart: WSL2 and Windows PowerShell

This build provides native Linux `ffmpeg`, `ffprobe`, and `ffplay` with NVIDIA encoding, decoding, and CUDA filters. Windows PowerShell commands below run the tools through WSL2; the outputs are not Windows `.exe` files.

### From Windows PowerShell

Run these commands from the folder containing the build scripts:

```powershell
# Build inside the selected WSL distro
.\build-wsl.ps1 -Distro Ubuntu-22.04 -Jobs 4

# Verify compiled features and GPU operation
.\verify.ps1 -Distro Ubuntu-22.04

# Also test video and audio playback
.\verify.ps1 -Distro Ubuntu-22.04 -Playback
```

Run the installed FFmpeg directly from PowerShell:

```powershell
wsl -d Ubuntu-22.04 --exec /home/hejun/.local/opt/ffmpeg/bin/ffmpeg -version
```

Replace `hejun` with your WSL username if different.

### From inside WSL2

Run from the folder containing the scripts:

```bash
# Build and verify
bash run-build-wsl.sh 4
bash verify-wsl.sh

# Optional graphical/audio playback test
bash verify-wsl.sh --playback
```

Use the installed tools:

```bash
"$HOME/.local/opt/ffmpeg/bin/ffmpeg" -version
"$HOME/.local/opt/ffmpeg/bin/ffprobe" -hide_banner input.mp4
"$HOME/.local/opt/ffmpeg/bin/ffplay" input.mp4
```

Optionally add them to the current shell's PATH:

```bash
export PATH="$HOME/.local/opt/ffmpeg/bin:$PATH"
```

### Output locations

| Contents | Location inside the selected WSL distro |
|---|---|
| Installed executables | `~/.local/opt/ffmpeg/bin/` |
| Build outputs and metadata | `~/ffmpeg-artifacts/` |
| Verification logs | `~/ffmpeg-artifacts/tests-*/` |

The PowerShell builder also copies outputs into an `out-<timestamp>-<id>` folder beside the scripts. Those copies remain Linux executables.

### Confirm which tests ran

Verification is fast because it uses short synthetic clips, mostly two seconds long, and single-image checks. Encoding runs as fast as the machine permits; only playback runs in real time.

Read `summary.csv` in the results directory printed by the verifier. For example, from PowerShell:

```powershell
wsl -d Ubuntu-22.04 --exec cat /home/hejun/ffmpeg-artifacts/tests-mmyrQ0wW/summary.csv
```

Replace the test-directory name with the one from your latest run.

- `PASS`: the command or validation succeeded.
- `SKIP`: the test was explicitly omitted.
- `FAIL`: the test failed; subsequent tests were not run.

GPU tests run by default. `-SkipGpu` in PowerShell or `--skip-gpu` in Bash explicitly skips them. Playback is skipped unless requested.

Look for passing `encode-h264`, `encode-hevc`, `decode-h264`, `decode-hevc`, `scale-cuda`, and `thumbnail-cuda` entries. Each command also has separate stdout and stderr logs in the same directory.