param(
    [ValidateRange(1,256)][int]$Jobs = 4,
    [string]$FFmpegRef = 'n9.0.1',
    [string]$HeadersRef = 'n13.0.19.0',
    [switch]$NoCache
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Get-Command docker -ErrorAction Stop | Out-Null
# Docker writes normal progress/warnings to stderr. In Windows PowerShell 5.1,
# redirecting stderr can turn those into NativeCommandError records. Check the
# native exit code explicitly instead of treating every stderr line as failure.
function Invoke-DockerChecked {
    param([string[]]$DockerArguments, [string]$FailureMessage)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & docker @DockerArguments
        $dockerExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($dockerExitCode -ne 0) {
        throw "$FailureMessage (Docker exit code $dockerExitCode)"
    }
}
Invoke-DockerChecked -DockerArguments @('info') -FailureMessage 'Docker is unavailable. Start Docker Desktop in Linux-container mode.' | Out-Null

# A new output folder prevents old executables being mistaken for this build.
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$outputDir = Join-Path $PSScriptRoot "out-$runId"
$dockerArgs = @('buildx','build','--platform','linux/amd64','--progress','plain',
    '--target','artifacts','--build-arg',"JOBS=$Jobs",
    '--build-arg',"FFMPEG_REF=$FFmpegRef",'--build-arg',"NV_HEADERS_REF=$HeadersRef",
    '--output',"type=local,dest=$outputDir")
if ($NoCache) { $dockerArgs += '--no-cache' }
$dockerArgs += $PSScriptRoot
Invoke-DockerChecked -DockerArguments $dockerArgs -FailureMessage 'Build failed. Do not use any partial output. Inspect the Docker build log.'
foreach ($exe in @('ffmpeg.exe','ffprobe.exe','ffplay.exe')) {
    if (-not (Test-Path (Join-Path $outputDir $exe))) { throw "Missing build output: $exe" }
}
Invoke-DockerChecked -DockerArguments @('version') -FailureMessage 'Could not record Docker version.' |
    Out-File -Encoding utf8 (Join-Path $outputDir 'metadata/docker-version.txt')
Write-Host "Build complete: $outputDir"
Write-Host "On the P4000 Windows machine, run: .\verify.ps1 -BinDir `"$outputDir`""
