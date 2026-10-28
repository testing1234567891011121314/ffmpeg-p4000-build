# Windows PowerShell 5.1+. Tests the recipe's features, not every NVIDIA codec/filter.
param(
    [Parameter(Mandatory=$true)][string]$BinDir,
    [ValidateRange(0,31)][int]$Gpu = 0,
    [switch]$Playback
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$BinDir = (Resolve-Path $BinDir).Path
$ffmpeg = Join-Path $BinDir 'ffmpeg.exe'
$ffprobe = Join-Path $BinDir 'ffprobe.exe'
$ffplay = Join-Path $BinDir 'ffplay.exe'
foreach ($exe in @($ffmpeg,$ffprobe,$ffplay)) {
    if (-not (Test-Path $exe -PathType Leaf)) { throw "Not found: $exe" }
}
$testDir = Join-Path $BinDir ('tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$results = New-Object 'System.Collections.Generic.List[object]'
$script:activeTest = 'Inventory'
$gpuText = [string]$Gpu

function Invoke-Logged {
    param([string]$Program, [string]$Name, [string[]]$NativeArgs)
    # Start-Process avoids PS 5.1 treating FFmpeg's normal stderr as a terminating
    # PowerShell error. Quote each argument to preserve paths containing spaces.
    $quoted = foreach ($arg in $NativeArgs) {
        if ($arg.Contains('"')) { throw 'Embedded double quotes are not supported in test arguments.' }
        '"' + ($arg -replace '(\\+)$', '$1$1') + '"'
    }
    $stdout = Join-Path $testDir "$Name.stdout.txt"
    $stderr = Join-Path $testDir "$Name.stderr.txt"
    $p = Start-Process -FilePath $Program -ArgumentList ($quoted -join ' ') `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($p.ExitCode -ne 0) {
        Get-Content $stderr -Tail 40 | ForEach-Object { Write-Host $_ }
        throw "$Name failed (exit $($p.ExitCode)); see $stderr"
    }
    return [string](Get-Content $stdout -Raw)
}
function Add-Pass {
    param([string]$Name)
    $results.Add([pscustomobject]@{ Test=$Name; Status='PASS'; Detail='' })
    Write-Host "PASS: $Name" -ForegroundColor Green
}
function Assert-Listed {
    param([string]$Text, [string]$Feature)
    if ($Text -notmatch ('(?m)^\s*(?:\S+\s+)?' + [regex]::Escape($Feature) + '(?:\s|$)')) {
        throw "Required compiled feature not found: $Feature"
    }
}
function Assert-Video {
    param([string]$Path, [string]$Codec, [int]$Width, [int]$Height, [string]$Name)
    if (-not (Test-Path $Path -PathType Leaf) -or (Get-Item $Path).Length -eq 0) {
        throw "Missing or empty output: $Path"
    }
    $json = Invoke-Logged -Program $ffprobe -Name $Name -NativeArgs @(
        '-v','error','-select_streams','v:0','-count_frames',
        '-show_entries','stream=codec_name,width,height,nb_read_frames','-of','json',$Path)
    $info = $json | ConvertFrom-Json
    if (@($info.streams).Count -ne 1) { throw "Expected one video stream: $Path" }
    $s = $info.streams[0]
    if ($s.codec_name -ne $Codec -or $s.width -ne $Width -or $s.height -ne $Height) {
        throw "Unexpected output codec or dimensions: $Path"
    }
    if ([int]$s.nb_read_frames -lt 1) { throw "Output contains no readable frames: $Path" }
}

Write-Host "Logs and results: $testDir"
Write-Host "Testing CUDA/NVENC device index $Gpu. Select the P4000 with -Gpu if necessary."
try {
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        # Advisory inventory; GPU runtime tests remain authoritative.
        try {
            $inventory = Invoke-Logged -Program $smi.Source -Name 'gpu-driver' -NativeArgs @(
                '--query-gpu=index,name,uuid,driver_version','--format=csv')
            Write-Host $inventory
        } catch { Write-Warning $_.Exception.Message }
    }
    $null = Invoke-Logged -Program $ffmpeg -Name 'buildconf' -NativeArgs @('-hide_banner','-buildconf')
    $script:activeTest = 'ffplay executable startup'
    $null = Invoke-Logged -Program $ffplay -Name 'ffplay-version' -NativeArgs @('-version')
    Add-Pass $script:activeTest
    $script:activeTest = 'Compiled features'
    $hw = Invoke-Logged -Program $ffmpeg -Name 'hwaccels' -NativeArgs @('-hide_banner','-hwaccels')
    $enc = Invoke-Logged -Program $ffmpeg -Name 'encoders' -NativeArgs @('-hide_banner','-encoders')
    $filters = Invoke-Logged -Program $ffmpeg -Name 'filters' -NativeArgs @('-hide_banner','-filters')
    $dec = Invoke-Logged -Program $ffmpeg -Name 'decoders' -NativeArgs @('-hide_banner','-decoders')
    Assert-Listed $hw 'cuda'
    foreach ($name in @('h264_nvenc','hevc_nvenc')) { Assert-Listed $enc $name }
    Assert-Listed $enc 'png'
    Assert-Listed $dec 'png'
    foreach ($name in @('scale_cuda','thumbnail_cuda','hwdownload')) { Assert-Listed $filters $name }
    Add-Pass 'Compiled CUDA/NVENC, required filters, and PNG encoder/decoder'
    # Dedicated CUVID wrappers are optional; native -hwaccel cuda uses NVDEC.
    if ($dec -notmatch '_cuvid') { Write-Host 'INFO: No CUVID wrappers listed; NVDEC is tested through native decoders.' }

    $source = Join-Path $testDir 'nvenc-h264.mp4'
    $hevc = Join-Path $testDir 'nvenc-hevc.mp4'
    $scaled = Join-Path $testDir 'nvdec-scale-hevc.mp4'
    $thumb = Join-Path $testDir 'thumbnail.png'
    $common = @('-hide_banner','-nostdin','-v','verbose','-xerror','-y')
    $decode = @('-hwaccel','cuda','-hwaccel_device',$gpuText,'-hwaccel_output_format','cuda')

    # Test the PNG dependency independently so CUDA failures remain distinguishable.
    $script:activeTest = 'PNG encoding and decoding'
    $pngTest = Join-Path $testDir 'png-test.png'
    $null = Invoke-Logged $ffmpeg 'png-roundtrip' ($common + @('-f','lavfi','-i',
        'testsrc=size=128x128:rate=1','-frames:v','1','-c:v','png','-update','1',$pngTest))
    Assert-Video $pngTest 'png' 128 128 'probe-png'
    $null = Invoke-Logged $ffmpeg 'decode-png' ($common + @('-i',$pngTest,'-f','null','-'))
    Add-Pass $script:activeTest

    $script:activeTest = 'H.264 NVENC'
    $null = Invoke-Logged $ffmpeg 'encode-h264' ($common + @('-f','lavfi','-i',
        'testsrc2=size=1280x720:rate=30','-t','2','-c:v','h264_nvenc','-gpu',$gpuText,$source))
    Assert-Video $source 'h264' 1280 720 'probe-h264'
    Add-Pass $script:activeTest

    $script:activeTest = 'HEVC NVENC'
    $null = Invoke-Logged $ffmpeg 'encode-hevc' ($common + @('-f','lavfi','-i',
        'testsrc2=size=1280x720:rate=30','-t','2','-c:v','hevc_nvenc','-gpu',$gpuText,$hevc))
    Assert-Video $hevc 'hevc' 1280 720 'probe-hevc'
    Add-Pass $script:activeTest

    # hwdownload requires hardware frames: software fallback cannot pass this graph.
    foreach ($sample in @(@('h264',$source),@('hevc',$hevc))) {
        $script:activeTest = "$($sample[0]) NVDEC and hardware-frame download"
        $null = Invoke-Logged $ffmpeg "decode-$($sample[0])" ($common + $decode + @(
            '-i',$sample[1],'-vf','hwdownload,format=nv12','-an','-f','null','-'))
        Add-Pass $script:activeTest
    }

    $script:activeTest = 'NVDEC -> scale_cuda -> HEVC NVENC'
    $null = Invoke-Logged $ffmpeg 'scale-cuda' ($common + $decode + @('-i',$source,
        '-vf','scale_cuda=640:360','-an','-c:v','hevc_nvenc','-gpu',$gpuText,$scaled))
    Assert-Video $scaled 'hevc' 640 360 'probe-scaled'
    Add-Pass $script:activeTest

    $script:activeTest = 'thumbnail_cuda -> PNG'
    $null = Invoke-Logged $ffmpeg 'thumbnail-cuda' ($common + $decode + @('-i',$source,
        '-vf','thumbnail_cuda=30,hwdownload,format=nv12,format=rgb24',
        '-frames:v','1','-c:v','png','-update','1',$thumb))
    Assert-Video $thumb 'png' 1280 720 'probe-thumbnail'
    Add-Pass $script:activeTest

    if ($Playback) {
        # Run on an interactive Windows desktop with working speakers/headphones.
        # Exit success is a process check, not proof of visible/audible output.
        $script:activeTest = 'ffplay sample generation'
        $avSample = Join-Path $testDir 'player-audio-video.mkv'
        $null = Invoke-Logged $ffmpeg 'make-player-sample' ($common + @(
            '-f','lavfi','-i','testsrc2=size=640x360:rate=30',
            '-f','lavfi','-i','sine=frequency=440:sample_rate=48000',
            '-t','3','-c:v','h264_nvenc','-gpu',$gpuText,'-c:a','pcm_s16le',$avSample))
        Assert-Video $avSample 'h264' 640 360 'probe-player-sample'
        Add-Pass $script:activeTest
        $script:activeTest = 'ffplay H.264 + audio process'
        Write-Host 'Playback: expect moving video and a quiet tone for 3 seconds.'
        $null = Invoke-Logged $ffplay 'ffplay-audio-video' @(
            '-hide_banner','-loglevel','verbose','-autoexit','-volume','10',
            '-window_title','FFplay audio and video test','-i',$avSample)
        Add-Pass $script:activeTest
        $script:activeTest = 'ffplay HEVC video process'
        Write-Host 'Playback: expect the scaled HEVC video for 2 seconds.'
        $null = Invoke-Logged $ffplay 'ffplay-hevc' @(
            '-hide_banner','-loglevel','verbose','-autoexit',
            '-window_title','FFplay HEVC test','-i',$scaled)
        Add-Pass $script:activeTest
        Write-Host 'Playback processes completed. Confirm that picture and sound were correct before accepting playback.'
    } else {
        Write-Host 'INFO: GUI/audio playback not tested. Rerun with -Playback on an interactive Windows desktop.'
    }
} catch {
    $results.Add([pscustomobject]@{ Test=$script:activeTest; Status='FAIL'; Detail=$_.Exception.Message })
    throw
} finally {
    $results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $testDir 'summary.csv')
    $results | Format-Table -AutoSize | Out-Host
    Write-Host "Results saved to: $testDir"
}
Write-Host 'All targeted feature tests passed. Inspect the generated videos and thumbnail.' -ForegroundColor Green
Write-Host 'Scope: 8-bit H.264/HEVC, NVDEC, scale_cuda and thumbnail_cuda; other listed codecs/filters are not runtime-tested.'
