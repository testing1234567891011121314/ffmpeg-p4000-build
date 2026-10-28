# Windows entry point for the native Linux verification suite.
param(
    [string]$BinDir = '',
    [ValidateRange(0,31)][int]$Gpu = 0,
    [string]$Distro = '',
    [switch]$Playback,
    [switch]$SkipGpu
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Get-Command wsl.exe -ErrorAction Stop | Out-Null
$distroArgs = @()
if ($Distro) { $distroArgs = @('-d', $Distro) }
function Quote-Bash([string]$Value) { return "'" + $Value.Replace("'", "'\''") + "'" }
function Convert-WslPath([string]$Value) {
    $pathArgs = $distroArgs + @('--exec', 'wslpath', '-u', $Value.Replace('\', '/'))
    $pathOutput = & wsl.exe @pathArgs
    if ($LASTEXITCODE -ne 0 -or $null -eq $pathOutput) {
        throw "Could not translate path: $Value"
    }
    $result = ([string]$pathOutput).Trim()
    return $result
}
$scriptDir = Convert-WslPath $PSScriptRoot
$cmd = 'cd ' + (Quote-Bash $scriptDir) + ' && bash ./verify-wsl.sh --gpu ' + $Gpu
if ($BinDir) {
    # Accept a Linux absolute path or an existing Windows path.
    if (-not $BinDir.StartsWith('/')) { $BinDir = Convert-WslPath (Resolve-Path $BinDir).Path }
    $cmd += ' --bin-dir ' + (Quote-Bash $BinDir)
}
if ($Playback) { $cmd += ' --playback' }
if ($SkipGpu) { $cmd += ' --skip-gpu' }
$runArgs = $runArgs = $distroArgs + @('--exec','bash','-c',$cmd)
$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & wsl.exe @runArgs
    $code = $LASTEXITCODE
} finally { $ErrorActionPreference = $previousPreference }
if ($code -ne 0) { throw "Linux verification failed (WSL exit $code). See the reported test log directory." }
