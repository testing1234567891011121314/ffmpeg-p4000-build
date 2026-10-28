## FFmpeg 9.1 with NVENC 13.0 Headers 

This repo provides the scripts required to compile ffmpeg with NVENC 13.0 headers so older gpus (Pascal) can run the latest ffmpeg with hardware support.

### For Windows
Run `.\build.ps1` from the windows/ subdirectory
Dependencies: This was compiled against cuda toolkit 12.9
Produces: ffmpeg.exe, ffplay.exe, ffprobe.exe

### For WSL
Refer to WSLQuickStart.md.
Dependencies: This was compiled against cuda toolkit 12.6
Produces: ffmpeg, ffplay, ffprobe