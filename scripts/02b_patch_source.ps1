#Requires -Version 5.1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
Ensure-Dirs
$log = Join-Path $LogRoot "02b_patch_source.log"
"" | Set-Content -Path $log -Encoding utf8

$setup = Join-Path $SrcDir "setup.py"
if (-not (Test-Path $setup)) { throw "Missing $setup" }

Write-Log "Patching $setup for Windows..." $log
& $PythonExe -c @"
from pathlib import Path
p = Path(r'$setup')
text = p.read_text(encoding='utf-8')
changed = []

old_nvcc = 'raw_output = subprocess.check_output([cuda_dir + \"/bin/nvcc\", \"-V\"], universal_newlines=True)'
new_nvcc = 'raw_output = subprocess.check_output([os.path.join(cuda_dir, \"bin\", \"nvcc\"), \"-V\"], universal_newlines=True)'
if old_nvcc in text:
    text = text.replace(old_nvcc, new_nvcc)
    changed.append('nvcc_path_join')

win_block = '''    if sys.platform == \"win32\" and os.getenv('DISTUTILS_USE_SDK') == '1':
        nvcc_flags.extend([\"-Xcompiler\", \"/Zc:__cplusplus\"])
        compiler_c17_flag=[\"-O2\", \"/std:c++17\", \"/Zc:__cplusplus\"]
'''
inject = win_block + '''
    # FlashAtten_Win: VS 2025/2026 is newer than CUDA 12.8 host_config allowlist.
    if sys.platform == \"win32\":
        nvcc_flags.append(\"-allow-unsupported-compiler\")
        nvcc_flags.extend([\"-Xcompiler\", \"/Zc:preprocessor\"])
'''
if 'allow-unsupported-compiler' not in text:
    if win_block not in text:
        raise SystemExit('Windows DISTUTILS_USE_SDK block not found')
    text = text.replace(win_block, inject, 1)
    changed.append('allow_unsupported_compiler')

p.write_text(text, encoding='utf-8')
(Path(r'$SrcDir') / 'FLASHATTEN_WIN_PATCHES.txt').write_text(
    'FlashAtten_Win patches\\n' + '\\n'.join(f'- {c}' for c in changed) + '\\n',
    encoding='utf-8'
)
print('changed', changed)
# syntax check
compile(text, str(p), 'exec')
print('syntax_ok')
"@

if ($LASTEXITCODE -ne 0) { throw "patch failed" }
Write-Log "Patch done" $log
