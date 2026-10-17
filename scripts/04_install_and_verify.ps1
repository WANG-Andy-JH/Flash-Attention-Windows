#Requires -Version 5.1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
Ensure-Dirs
$log = Join-Path $LogRoot "04_install_and_verify.log"
"" | Set-Content $log

$wheel = Get-ChildItem $DistRoot -Filter "flash_attn*.whl" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $wheel) { throw "No wheel in $DistRoot. Run build first." }

Write-Log "Installing $($wheel.FullName)" $log
$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $PythonExe -m pip install --force-reinstall --no-deps $wheel.FullName 2>&1 | Tee-Object -FilePath $log -Append
$pipExit = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($pipExit -ne 0) { throw "pip install failed with exit code $pipExit" }

Write-Log "Verifying import + varlen API (used by PTv3)..." $log
& $PythonExe -c @"
import torch, flash_attn
print('flash_attn', getattr(flash_attn, '__version__', 'unknown'))
print('torch', torch.__version__, 'cuda', torch.version.cuda)
from flash_attn.flash_attn_interface import flash_attn_varlen_qkvpacked_func
print('flash_attn_varlen_qkvpacked_func', flash_attn_varlen_qkvpacked_func)

if not torch.cuda.is_available():
    raise SystemExit('CUDA not available; import-only OK')

# Minimal smoke: tiny varlen forward
qkv = torch.randn(32, 3, 4, 32, device='cuda', dtype=torch.float16)
cu_seqlens = torch.tensor([0, 16, 32], device='cuda', dtype=torch.int32)
out = flash_attn_varlen_qkvpacked_func(qkv, cu_seqlens, max_seqlen=16, dropout_p=0.0, causal=False)
print('smoke_out', tuple(out.shape), out.dtype)
print('VERIFY_OK')
"@ 2>&1 | Tee-Object -FilePath $log -Append

Write-Log "Install + verify done" $log
