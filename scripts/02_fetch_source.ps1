#Requires -Version 5.1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
Ensure-Dirs
$log = Join-Path $LogRoot "02_fetch_source.log"
"" | Set-Content -Path $log -Encoding utf8

Write-Log "Fetching flash-attn==$FlashAttnVersion sdist..." $log

$downloadDir = Join-Path $SourceRoot "download"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
$sdistPath = Join-Path $downloadDir "flash_attn-$FlashAttnVersion.tar.gz"

if (-not (Test-Path $sdistPath) -or (Get-Item $sdistPath).Length -lt 1MB) {
    $url = "https://files.pythonhosted.org/packages/source/f/flash-attn/flash_attn-$FlashAttnVersion.tar.gz"
    Write-Log "Downloading $url" $log
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        curl.exe -L --retry 3 -o $sdistPath $url
        if ($LASTEXITCODE -ne 0) { throw "curl failed: $LASTEXITCODE" }
    } finally {
        $ErrorActionPreference = $prev
    }
}

if (-not (Test-Path $sdistPath)) { throw "sdist missing: $sdistPath" }
Write-Log "Using sdist $sdistPath ($((Get-Item $sdistPath).Length) bytes)" $log

# Short extract root avoids WIN32 MAX_PATH failures on composable_kernel (ROCm-only) paths.
$extractRoot = "D:\fa_extract"
if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
if (Test-Path $SrcDir) { Remove-Item -Recurse -Force $SrcDir }
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $SrcDir -Parent) -ErrorAction SilentlyContinue | Out-Null

Write-Log "Extracting CUDA-needed files to $SrcDir (skip ROCm composable_kernel)..." $log
& $PythonExe -c @"
import tarfile, pathlib, shutil

sdist = pathlib.Path(r'$sdistPath')
extract_root = pathlib.Path(r'$extractRoot')
target = pathlib.Path(r'$SrcDir')
skip_prefix = 'flash_attn-$FlashAttnVersion/csrc/composable_kernel/'

with tarfile.open(sdist, 'r:gz') as tf:
    for m in tf.getmembers():
        name = m.name.replace('\\\\', '/')
        if name.startswith(skip_prefix) or '/composable_kernel/' in name:
            continue
        # Guard remaining long paths
        if len(str(extract_root / name)) > 240:
            continue
        tf.extract(m, extract_root)

extracted = extract_root / 'flash_attn-$FlashAttnVersion'
if not (extracted / 'setup.py').exists():
    raise SystemExit(f'setup.py missing under {extracted}')
if target.exists():
    shutil.rmtree(target)
shutil.move(str(extracted), str(target))
shutil.rmtree(extract_root, ignore_errors=True)
print('extracted', target)
print('cutlass', (target / 'csrc' / 'cutlass' / 'include').exists())
print('flash_api', (target / 'csrc' / 'flash_attn' / 'flash_api.cpp').exists())
"@

if ($LASTEXITCODE -ne 0) { throw "extract failed" }
if (-not (Test-Path (Join-Path $SrcDir "setup.py"))) { throw "setup.py missing after extract" }
if (-not (Test-Path (Join-Path $SrcDir "csrc\cutlass\include"))) { throw "cutlass headers missing" }

Write-Log "Source ready at $SrcDir" $log
