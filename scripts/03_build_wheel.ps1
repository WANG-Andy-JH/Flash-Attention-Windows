#Requires -Version 5.1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
Ensure-Dirs
$log = Join-Path $LogRoot ("03_build_wheel_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
"" | Set-Content -Path $log -Encoding utf8

if (-not (Test-Path (Join-Path $SrcDir "setup.py"))) {
    throw "Source missing at $SrcDir. Run scripts/02_fetch_source.ps1 first."
}
if (-not $VsVcVars) { throw "vcvars64.bat not found" }

$cudaHome = Get-CudaHome
if (-not $cudaHome) { throw "CUDA_HOME/nvcc not found. Run scripts/01_install_build_deps.ps1" }

# nvcc intermediates + .obj can need tens of GB; abort early if the build drive is nearly full.
$srcDrive = (Split-Path -Qualifier $SrcDir).TrimEnd('\')
$driveInfo = Get-PSDrive -Name $srcDrive.TrimEnd(':') -ErrorAction SilentlyContinue
$minFreeGb = if ($env:FLASHATTN_MIN_FREE_GB) { [double]$env:FLASHATTN_MIN_FREE_GB } else { 40 }
if ($driveInfo -and (($driveInfo.Free / 1GB) -lt $minFreeGb)) {
    throw ("Drive {0} has only {1:N1} GB free; need >= {2} GB for flash-attn build. Free space or set FLASHATTN_SRC to another drive." -f $srcDrive, ($driveInfo.Free / 1GB), $minFreeGb)
}

Write-Log "Building flash-attn wheel" $log
Write-Log "Python=$PythonExe" $log
Write-Log "CUDA_HOME=$cudaHome" $log
Write-Log "SrcDir=$SrcDir" $log
Write-Log "FLASH_ATTN_CUDA_ARCHS=$FlashAttnCudaArchs" $log
Write-Log "TORCH_CUDA_ARCH_LIST=$TorchCudaArchList" $log
Write-Log "MAX_JOBS=$MaxJobs NVCC_THREADS=$NvccThreads" $log
Write-Log "VsVcVars=$VsVcVars" $log
Write-Log ("Drive {0} free={1:N1} GB" -f $srcDrive, ($driveInfo.Free / 1GB)) $log

$keepBuild = ($env:FLASHATTN_KEEP_BUILD -eq "1")
if (-not $keepBuild) {
    foreach ($name in @("build", "dist", "*.egg-info")) {
        Get-ChildItem $SrcDir -Filter $name -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Cleaned previous build/dist under $SrcDir" $log
} else {
    Write-Log "FLASHATTN_KEEP_BUILD=1 — keeping existing build tree for incremental compile" $log
}

New-Item -ItemType Directory -Force -Path $ShortLogRoot, $BuildTempRoot | Out-Null

$cmdPath = Join-Path $env:SystemRoot "System32\cmd.exe"
$buildBat = Join-Path $ShortLogRoot "build_inner.bat"
$wheelOut = $DistRoot
$combinedLog = Join-Path $ShortLogRoot "build_combined.log"

# Use cmd + vcvars so cl.exe/nvcc see the MSVC toolchain (required on Windows).
@"
@echo off
setlocal EnableExtensions
call "$VsVcVars"
if errorlevel 1 exit /b 1

set "CUDA_HOME=$cudaHome"
set "CUDA_PATH=$cudaHome"
set "PATH=$cudaHome\bin;%PATH%"
REM conda CUDA on Windows nests nv/target under include\targets\x64
set "INCLUDE=$cudaHome\include\targets\x64;$cudaHome\include;%INCLUDE%"
set "CPATH=$cudaHome\include\targets\x64;$cudaHome\include;%CPATH%"
REM conda CUDA keeps cudart.lib in Library\lib (not lib\x64); MSVC link reads LIB=
set "LIB=$cudaHome\lib;%LIB%"
set "LIBRARY_PATH=$cudaHome\lib;%LIBRARY_PATH%"
set "DISTUTILS_USE_SDK=1"
set "FLASH_ATTENTION_FORCE_BUILD=TRUE"
set "FLASH_ATTENTION_SKIP_CUDA_BUILD=FALSE"
set "FLASH_ATTN_CUDA_ARCHS=$FlashAttnCudaArchs"
set "TORCH_CUDA_ARCH_LIST=$TorchCudaArchList"
set "MAX_JOBS=$MaxJobs"
set "NVCC_THREADS=$NvccThreads"
set "KMP_DUPLICATE_LIB_OK=TRUE"
REM Keep nvcc temp files off a full D: drive.
set "TEMP=$BuildTempRoot"
set "TMP=$BuildTempRoot"
set "PIP_PROGRESS_BAR=off"

cd /d "$SrcDir"
"$PythonExe" -m pip wheel . --no-build-isolation --no-deps -v -w "$wheelOut"
exit /b %ERRORLEVEL%
"@ | Set-Content -Path $buildBat -Encoding ASCII

Write-Log "Launching $buildBat (this often takes 30-120+ minutes)..." $log
Write-Log "Combined compiler log: $combinedLog" $log

"" | Set-Content -Path $combinedLog -Encoding utf8

$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    # Single combined redirect so ninja/nvcc errors are not lost to an empty stderr file.
    & $cmdPath /c "`"$buildBat`" >> `"$combinedLog`" 2>&1"
    $exitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $prev
}

try {
    Add-Content -Path $log -Value "---- combined log (tail) ----" -ErrorAction SilentlyContinue
    if (Test-Path $combinedLog) {
        Get-Content $combinedLog -Tail 120 -ErrorAction SilentlyContinue | Add-Content -Path $log -ErrorAction SilentlyContinue
    }
    Add-Content -Path $log -Value "full_log=$combinedLog" -ErrorAction SilentlyContinue
} catch {
    Write-Host "Warning: could not append compiler logs to $log"
}

if ($exitCode -ne 0) {
    throw "Wheel build failed with exit code $exitCode. See $combinedLog"
}

$wheels = Get-ChildItem $wheelOut -Filter "flash_attn*.whl" | Sort-Object LastWriteTime -Descending
if (-not $wheels) { throw "Build reported success but no flash_attn*.whl in $wheelOut" }

Write-Log "Built wheel(s):" $log
$wheels | ForEach-Object { Write-Log $_.FullName $log }

$latest = $wheels[0]
$manifest = @"
flash_attn_wheel=$($latest.Name)
flash_attn_version=$FlashAttnVersion
FLASH_ATTN_CUDA_ARCHS=$FlashAttnCudaArchs
TORCH_CUDA_ARCH_LIST=$TorchCudaArchList
built_at=$(Get-Date -Format o)
python=$(& $PythonExe -c "import sys; print(sys.version.split()[0])")
torch=$(& $PythonExe -c "import torch; print(torch.__version__)")
cuda=$(& $PythonExe -c "import torch; print(torch.version.cuda)")
target_gpus=RTX40(sm80-compat)+RTX50(sm120)
"@
$manifestPath = Join-Path $DistRoot "wheel_manifest.txt"
$manifest | Set-Content -Path $manifestPath -Encoding UTF8
Write-Log "Manifest: $manifestPath" $log
Write-Log "DONE" $log
