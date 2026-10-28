param(
    [ValidateRange(1,256)][int]$Jobs = 4,
    [string]$FFmpegRef = 'n9.0.1',
    [string]$HeadersRef = 'n13.0.19.0',
    [string]$Distro = '',
    [switch]$Clean
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Get-Command wsl.exe -ErrorAction Stop | Out-Null
$distroArgs = @()
if ($Distro) { $distroArgs = @('-d', $Distro) }
function Quote-Bash([string]$Value) {
    return "'" + $Value.Replace("'", "'\''") + "'"
}
function Invoke-WslChecked {
    param([string[]]$WslArguments, [string]$FailureMessage)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & wsl.exe @WslArguments
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) { throw "$FailureMessage (WSL exit $code)" }
}

$pathArgs = $distroArgs + @('--exec', 'wslpath', '-u', $PSScriptRoot.Replace('\', '/'))
$pathOutput = & wsl.exe @pathArgs
if ($LASTEXITCODE -ne 0 -or $null -eq $pathOutput) {
    throw 'Could not translate script directory with wslpath.'
}
$wslScriptDir = ([string]$pathOutput).Trim()

$cleanFlag = ''
if ($Clean) { $cleanFlag = '--clean' }
$runCmd = 'set -e; cd ' + (Quote-Bash $wslScriptDir) + '; ' +
    'FFMPEG_REF=' + (Quote-Bash $FFmpegRef) + ' NV_HEADERS_REF=' + (Quote-Bash $HeadersRef) +
    " bash ./run-build-wsl.sh $Jobs $cleanFlag"
Invoke-WslChecked -WslArguments ($distroArgs + @('--','bash','-c',$runCmd)) -FailureMessage 'Build failed'
# Ask the same distro and user that built the files for their output location.
$artifactCmd = 'set -e; cd ' + (Quote-Bash $wslScriptDir) +
    '; source ./build-env.sh; wslpath -w "$ARTIFACTS_DIR"'
$artifactArgs = $distroArgs + @('--exec','bash','-c',$artifactCmd)
$artifactOutput = & wsl.exe @artifactArgs
if ($LASTEXITCODE -ne 0 -or $null -eq $artifactOutput) {
    throw 'Could not resolve WSL artifacts.'
}
$winArtifactsPath = ([string]$artifactOutput).Trim()
if ($LASTEXITCODE -ne 0 -or -not $winArtifactsPath) { throw 'Could not resolve WSL artifacts.' }
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$outputDir = Join-Path $PSScriptRoot "out-$runId"
New-Item -ItemType Directory -Path $outputDir | Out-Null
Copy-Item -Path (Join-Path $winArtifactsPath '*') -Destination $outputDir -Recurse -Force
foreach ($binary in @('ffmpeg','ffprobe','ffplay')) {
    if (-not (Test-Path (Join-Path $outputDir $binary) -PathType Leaf)) { throw "Missing output: $binary" }
}
Write-Host "Build complete. Linux binaries copied to: $outputDir"
Write-Host 'Run verify.ps1 with the same -Distro value; its default tests the original WSL output.'
