#Requires -Version 5.1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
Ensure-Dirs
$log = Join-Path $LogRoot "00_check_env.log"
"" | Set-Content $log

Write-Log "Python: $PythonExe" $log
if (-not (Test-Path $PythonExe)) {
    throw "Python not found: $PythonExe. Set FLASHATTN_PYTHON to your env python.exe"
}

& $PythonExe -c @"
import sys, torch
print('python', sys.version)
print('torch', torch.__version__)
print('torch.cuda', torch.version.cuda)
print('cuda_available', torch.cuda.is_available())
if torch.cuda.is_available():
    print('gpu', torch.cuda.get_device_name(0))
    print('capability', torch.cuda.get_device_capability(0))
print('cxx11_abi', getattr(torch._C, '_GLIBCXX_USE_CXX11_ABI', 'n/a'))
"@ 2>&1 | Tee-Object -FilePath $log -Append

Write-Log "FLASH_ATTN_CUDA_ARCHS=$FlashAttnCudaArchs" $log
Write-Log "TORCH_CUDA_ARCH_LIST=$TorchCudaArchList" $log
Write-Log "VsVcVars=$VsVcVars" $log
if (-not $VsVcVars) { throw "Visual Studio vcvars64.bat not found. Install VS C++ build tools." }

$cudaHome = Get-CudaHome
Write-Log "CUDA_HOME=$cudaHome" $log
if (-not $cudaHome) {
    Write-Log "WARNING: nvcc not found. Run scripts/01_install_build_deps.ps1 first." $log
    exit 2
}

& (Join-Path $cudaHome "bin\nvcc.exe") -V 2>&1 | Tee-Object -FilePath $log -Append
Write-Log "Environment check OK" $log
