# Run the official FATE suite against a Windows cross-build using Wine in Docker.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BuildDir,
    [ValidateRange(1,64)][int]$Jobs = 4,
    [string]$BuilderImage = 'ffmpeg-p4000-builder',
    [string]$SamplesVolume = 'ffmpeg-fate-samples',
    [switch]$ReuseBuilderImage,
    [switch]$SkipSampleSync,
    [string]$OutputDir
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$BuildDir = (Resolve-Path $BuildDir).Path
if (-not (Test-Path (Join-Path $BuildDir 'Dockerfile'))) { throw 'BuildDir must contain the FFmpeg recipe Dockerfile.' }
if ($SamplesVolume -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]+$') { throw 'Invalid Docker volume name.' }
function Invoke-DockerChecked {
    param([string[]]$DockerArguments)
    $old = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & docker @DockerArguments
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw "Docker exited $code. Review the build output or FATE results." }
}
Get-Command docker -ErrorAction Stop | Out-Null
if (-not $OutputDir) { $OutputDir = Join-Path $PWD ('fate-results-' + [guid]::NewGuid().ToString('N')) }
if (Test-Path $OutputDir) { throw 'Use a new output directory.' }
New-Item -ItemType Directory -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path
if ($OutputDir.Contains(',')) { throw 'Docker mount paths must not contain commas.' }
Write-Host "Results: $OutputDir"
if (-not $ReuseBuilderImage) {
    Invoke-DockerChecked @('buildx','build','--platform','linux/amd64','--target','build','--load',
        '--progress','plain','--build-arg',"JOBS=$Jobs",'-t',$BuilderImage,$BuildDir)
}
$testImage = 'ffmpeg-fate-' + [guid]::NewGuid().ToString('N').Substring(0,12)
Invoke-DockerChecked @('buildx','build','--platform','linux/amd64','--load','--progress','plain',
    '--build-arg',"BUILDER_IMAGE=$BuilderImage",'-f',(Join-Path $PSScriptRoot 'Dockerfile.fate'),
    '-t',$testImage,$PSScriptRoot)
Invoke-DockerChecked @('image','inspect',$testImage) |
    Out-File -Encoding UTF8 (Join-Path $OutputDir 'test-image.json')
Invoke-DockerChecked @('volume','create',$SamplesVolume) | Out-Null
$sync = 'yes'
if ($SkipSampleSync) { $sync = 'no' }
Invoke-DockerChecked @('run','--rm','--platform','linux/amd64',
    '--mount',"type=volume,source=$SamplesVolume,target=/samples",
    '--mount',"type=bind,source=$OutputDir,target=/results",
    $testImage,[string]$Jobs,$sync)
$status = Get-Content (Join-Path $OutputDir 'status.txt') -Raw
if ($status -notmatch 'stage=completed' -or $status -notmatch 'exit_code=0') {
    throw 'FATE did not finish successfully; inspect status.txt and fate.log.'
}
Write-Host "PASS: FATE completed. Results and tested build: $OutputDir"
Write-Host "Test image retained for diagnosis: $testImage"
Write-Host "Samples remain in Docker volume: $SamplesVolume"
Write-Host 'This does not validate Windows NVIDIA drivers or interactive ffplay playback.'
