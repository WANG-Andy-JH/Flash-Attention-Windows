#Requires -Version 5.1
<#
.SYNOPSIS
  Build a Windows flash-attn wheel for RTX 40 + RTX 50 series.

.USAGE
  powershell -ExecutionPolicy Bypass -File .\build.ps1
  powershell -ExecutionPolicy Bypass -File .\build.ps1 -SkipDeps
  powershell -ExecutionPolicy Bypass -File .\build.ps1 -InstallAfter
#>
param(
    [switch]$SkipDeps,
    [switch]$SkipFetch,
    [switch]$InstallAfter
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "=== FlashAtten_Win build ===" -ForegroundColor Cyan
if (-not $SkipDeps) {
    & .\scripts\01_install_build_deps.ps1
    & .\scripts\01b_install_vs2022_buildtools.ps1
}
& .\scripts\00_check_env.ps1
if (-not $SkipFetch) {
    & .\scripts\02_fetch_source.ps1
    & .\scripts\02b_patch_source.ps1
}
& .\scripts\03_build_wheel.ps1
if ($InstallAfter) {
    & .\scripts\04_install_and_verify.ps1
}

Write-Host "Wheel output: $(Join-Path $PSScriptRoot 'dist')" -ForegroundColor Green
