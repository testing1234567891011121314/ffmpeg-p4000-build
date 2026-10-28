# Windows PowerShell 5.1+. Video-only CPU decoder regression comparisons.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BinDir,
    [Parameter(Mandatory=$true)][string]$ReferenceFFmpeg,
    [Parameter(Mandatory=$true)][string[]]$Inputs,
    [string]$OutputDir,
    [ValidateRange(1,256)][int]$Threads = 4
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ffmpeg = Join-Path (Resolve-Path $BinDir).Path 'ffmpeg.exe'
$ffprobe = Join-Path (Resolve-Path $BinDir).Path 'ffprobe.exe'
$reference = (Resolve-Path $ReferenceFFmpeg).Path
foreach ($file in @($ffmpeg,$ffprobe,$reference)) {
    if (-not (Test-Path $file -PathType Leaf)) { throw "Missing executable: $file" }
}
if ((Get-FileHash $ffmpeg -Algorithm SHA256).Hash -eq (Get-FileHash $reference -Algorithm SHA256).Hash) {
    throw 'ReferenceFFmpeg is identical to the candidate. Supply a separate trusted FFmpeg build.'
}
$media = @($Inputs | ForEach-Object { (Resolve-Path $_).Path } | Select-Object -Unique)
if ($media.Count -eq 0) { throw 'No input media selected.' }
if (-not $OutputDir) { $OutputDir = Join-Path $PWD ('regression-' + [guid]::NewGuid().ToString('N')) }
if (Test-Path $OutputDir) { throw 'Use a new output directory to avoid mixing results.' }
New-Item -ItemType Directory -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path
$results = New-Object 'System.Collections.Generic.List[object]'
$failed = $false

function Invoke-Logged {
    param([string]$Program,[string]$Name,[string[]]$NativeArgs)
    $quoted = foreach ($arg in $NativeArgs) {
        if ($arg.Contains('"')) { throw 'Embedded quotes are not supported in arguments.' }
        '"' + ($arg -replace '(\\+)$','$1$1') + '"'
    }
    $stdout = Join-Path $OutputDir "$Name.stdout.txt"
    $stderr = Join-Path $OutputDir "$Name.stderr.txt"
    @{program=$Program;arguments=$NativeArgs} | ConvertTo-Json -Depth 5 |
        Set-Content -Encoding UTF8 (Join-Path $OutputDir "$Name.command.json")
    $p = Start-Process -FilePath $Program -ArgumentList ($quoted -join ' ') `
        -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($p.ExitCode -ne 0) { throw "$Name exited $($p.ExitCode). See $stderr" }
    return [string](Get-Content $stdout -Raw)
}
function Read-Frames {
    param([string]$Path)
    $records = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        $fields = @($line.Split(',') | ForEach-Object { $_.Trim() })
        if ($fields.Count -ne 6) { throw "Unexpected framehash record in $Path" }
        # Compare decoded frame size and hash in sequence; retain timestamps in file.
        $records.Add("$($fields[4]),$($fields[5])")
    }
    if ($records.Count -eq 0) { throw "No decoded frames in $Path" }
    return $records
}
function Compare-Frames {
    param([string]$Expected,[string]$Actual)
    $a = @(Read-Frames $Expected); $b = @(Read-Frames $Actual)
    if ($a.Count -ne $b.Count) { throw "Frame count differs: $($a.Count) versus $($b.Count)" }
    for ($j=0; $j -lt $a.Count; $j++) {
        if ($a[$j] -cne $b[$j]) { throw "Decoded pixels differ at frame $j (zero-based)." }
    }
    return $a.Count
}

try {
    foreach ($pair in @(@('candidate',$ffmpeg),@('reference',$reference))) {
        $null = Invoke-Logged $pair[1] "$($pair[0])-version" @('-version')
        Get-FileHash $pair[1] -Algorithm SHA256 | Format-List | Out-String |
            Set-Content (Join-Path $OutputDir "$($pair[0])-sha256.txt")
    }
    for ($i=0; $i -lt $media.Count; $i++) {
        $inputFile = $media[$i]
        Write-Host "Testing $inputFile"
        try {
            $json = Invoke-Logged $ffprobe "$i-probe" @('-v','error','-select_streams','v:0',
                '-show_entries','stream=codec_name,pix_fmt,width,height','-of','json',$inputFile)
            $streams = @(($json | ConvertFrom-Json).streams)
            if ($streams.Count -ne 1) { throw 'Expected a readable first video stream.' }
            $pixelFormat = [string]$streams[0].pix_fmt
            if ([string]::IsNullOrWhiteSpace($pixelFormat)) { throw 'Unknown pixel format.' }
            # Use the input pixel format to avoid hiding differences by downconverting
            # all recordings to 8-bit YUV. Hardware acceleration is explicitly off.
            $tail = @('-i',$inputFile,'-map','0:v:0','-an','-sn','-dn','-vsync','0',
                '-c:v','rawvideo','-threads:v','1','-pix_fmt',$pixelFormat,
                '-f','framehash','-hash','sha256')
            $common = @('-hide_banner','-nostdin','-v','warning','-xerror','-y')
            $normal = Join-Path $OutputDir "$i-candidate.framehash"
            $baseline = Join-Path $OutputDir "$i-reference.framehash"
            $scalar = Join-Path $OutputDir "$i-candidate-cpuflags0.framehash"
            $threaded = Join-Path $OutputDir "$i-candidate-threaded.framehash"
            $null = Invoke-Logged $ffmpeg "$i-candidate" ($common + @('-hwaccel','none','-threads','1') + $tail + @($normal))
            $null = Invoke-Logged $reference "$i-reference" ($common + @('-hwaccel','none','-threads','1') + $tail + @($baseline))
            $null = Invoke-Logged $ffmpeg "$i-cpuflags0" ($common + @('-cpuflags','0','-hwaccel','none','-threads','1') + $tail + @($scalar))
            $null = Invoke-Logged $ffmpeg "$i-threaded" ($common + @('-hwaccel','none','-threads',[string]$Threads) + $tail + @($threaded))
            $count = Compare-Frames $baseline $normal
            $null = Compare-Frames $normal $scalar
            $null = Compare-Frames $normal $threaded
            $results.Add([pscustomobject]@{Input=$inputFile;Status='PASS';Frames=$count;Detail='Reference, cpuflags=0 and multithreaded pixel hashes agree'})
        } catch {
            $failed = $true
            $results.Add([pscustomobject]@{Input=$inputFile;Status='FAIL';Frames=0;Detail=$_.Exception.Message})
            Write-Warning $_.Exception.Message
        }
    }
} finally {
    $results | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutputDir 'summary.csv')
    $results | Format-Table -AutoSize | Out-Host
    Write-Host "Results: $OutputDir"
}
if ($failed) { throw 'One or more regression checks failed. Review the logs and framehash files.' }
Write-Host 'PASS: video pixel comparisons for all supplied inputs.'
Write-Host 'Not covered: audio, timestamp equivalence, seeking, GPU decoding, all inputs, or memory safety.'
