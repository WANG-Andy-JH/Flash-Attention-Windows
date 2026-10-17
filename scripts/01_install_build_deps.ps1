#Requires -Version 5.1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
Ensure-Dirs
$log = Join-Path $LogRoot "01_install_build_deps.log"
"" | Set-Content $log

function Invoke-NativeLogged {
    param(
        [scriptblock]$Command,
        [string]$LogFile
    )
    # pip/conda often write progress to stderr; do not treat that as failure.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Command 2>&1 | ForEach-Object {
            $text = "$_"
            Write-Host $text
            Add-Content -Path $LogFile -Value $text
        }
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE"
        }
    } finally {
        $ErrorActionPreference = $prev
    }
}

Write-Log "Installing Python build deps into Pointcept env..." $log
# Keep setuptools relatively conservative; very new setuptools can break torch.utils.cpp_extension.
Invoke-NativeLogged -LogFile $log -Command {
    & $PythonExe -m pip install -U "pip" "wheel" "packaging" "ninja" "psutil" "setuptools>=60,<70"
}

$cudaHome = Get-CudaHome
if ($cudaHome) {
    Write-Log "nvcc already present at $cudaHome" $log
} else {
    Write-Log "Installing CUDA toolkit 12.8 into conda env Pointcept (needed for sm_120)..." $log
    Invoke-NativeLogged -LogFile $log -Command {
        conda install -n Pointcept -c nvidia cuda-toolkit=12.8.2 --yes
    }
    $cudaHome = Get-CudaHome
    if (-not $cudaHome) {
        throw "CUDA toolkit install finished but nvcc still not found. Install CUDA Toolkit 12.8+ system-wide and set CUDA_HOME."
    }
}

Write-Log "CUDA_HOME=$cudaHome" $log
& (Join-Path $cudaHome "bin\nvcc.exe") -V 2>&1 | ForEach-Object { Write-Host $_; Add-Content -Path $log -Value "$_" }

# conda win CUDA nests nv/target under include\targets\x64; MSVC expects include\nv
$nvSrc = Join-Path $cudaHome "include\targets\x64\nv"
$nvDst = Join-Path $cudaHome "include\nv"
if ((Test-Path $nvSrc) -and -not (Test-Path $nvDst)) {
    Write-Log "Creating junction $nvDst -> $nvSrc" $log
    cmd /c mklink /J "$nvDst" "$nvSrc" | ForEach-Object { Write-Host $_; Add-Content -Path $log -Value "$_" }
}

Write-Log "Build deps ready" $log
