# Flash Attention Windows build configuration
# Target: RTX 40-series (sm_80 binary compat within CC 8.x) + RTX 50-series (sm_120)

$ErrorActionPreference = "Stop"

$FlashAttenRoot = $PSScriptRoot
$SourceRoot = Join-Path $FlashAttenRoot "source"
$DistRoot = Join-Path $FlashAttenRoot "dist"
$LogRoot = Join-Path $FlashAttenRoot "logs"
# Windows MAX_PATH breaks flash-attn sdist extraction under deep project paths.
# Keep the working tree on a short drive path; scripts still live under FlashAtten_Win.
# Prefer C: — D: filled up during nvcc (~3GB free) and aborted the previous build.
$SrcDir = if ($env:FLASHATTN_SRC) { $env:FLASHATTN_SRC } else { "fa_src" }
$ShortLogRoot = if ($env:FLASHATTN_BUILD_LOGS) { $env:FLASHATTN_BUILD_LOGS } else { "fa_build_logs" }
$BuildTempRoot = if ($env:FLASHATTN_TMP) { $env:FLASHATTN_TMP } else { "fa_tmp" }

# Match Pointcept inference stack unless overridden
$PythonExe = if ($env:FLASHATTN_PYTHON) {
    $env:FLASHATTN_PYTHON
} else {
    Join-Path $env:USERPROFILE ".conda\envs\Pointcept\python.exe"
}

$FlashAttnVersion = if ($env:FLASHATTN_VERSION) { $env:FLASHATTN_VERSION } else { "2.8.3" }

# flash-attn setup.py reads FLASH_ATTN_CUDA_ARCHS as "80;90;100;120" style tags.
# 80  -> Ampere SASS; runs on Ada/40-series via CUDA major-8 compatibility
# 120 -> Blackwell / RTX 50-series (requires CUDA toolkit >= 12.8)
$FlashAttnCudaArchs = if ($env:FLASH_ATTN_CUDA_ARCHS) { $env:FLASH_ATTN_CUDA_ARCHS } else { "80;120" }
$TorchCudaArchList = if ($env:TORCH_CUDA_ARCH_LIST) { $env:TORCH_CUDA_ARCH_LIST } else { "8.0;12.0" }

$MaxJobs = if ($env:MAX_JOBS) { $env:MAX_JOBS } else { "1" }
$NvccThreads = if ($env:NVCC_THREADS) { $env:NVCC_THREADS } else { "1" }

function Test-VsVcVars {
    param([string]$VcVarsPath)
    if (-not (Test-Path $VcVarsPath)) { return $false }
    # vcvars64.bat is normally a tiny wrapper (~40 bytes) that calls vcvarsall.bat.
    # Do NOT reject by file size. Validate by locating Hostx64\x64\cl.exe nearby,
    # or by invoking vcvars when needed.
    $buildDir = Split-Path $VcVarsPath -Parent
    $vcRoot = Split-Path (Split-Path $buildDir -Parent) -Parent  # ...\VC
    $cl = Get-ChildItem (Join-Path $vcRoot "Tools\MSVC") -Filter cl.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\Hostx64\\x64\\cl\.exe$' } |
        Select-Object -First 1
    return $null -ne $cl
}

function Resolve-VsVcVars {
    $candidates = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat",
        # VS 2025/2026 last: CUDA 12.8 cudafe++ often crashes with these toolchains
        "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
    )
    if ($env:FLASHATTN_VCVARS -and (Test-Path $env:FLASHATTN_VCVARS)) {
        return $env:FLASHATTN_VCVARS
    }
    foreach ($c in $candidates) {
        if (Test-VsVcVars $c) { return $c }
    }
    # Fallback: first existing path even if cl probe failed
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

$VsVcVars = Resolve-VsVcVars

function Get-CudaHome {
    if ($env:CUDA_HOME -and (Test-Path (Join-Path $env:CUDA_HOME "bin\nvcc.exe"))) {
        return $env:CUDA_HOME
    }
    if ($env:CUDA_PATH -and (Test-Path (Join-Path $env:CUDA_PATH "bin\nvcc.exe"))) {
        return $env:CUDA_PATH
    }

    $candidates = @(
        (Join-Path $env:USERPROFILE ".conda\envs\Pointcept\Library"),
        (Join-Path $env:USERPROFILE ".conda\envs\Pointcept"),
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.9"
    )
    foreach ($root in $candidates) {
        $nvcc = Join-Path $root "bin\nvcc.exe"
        if (Test-Path $nvcc) { return $root }
    }

    $found = Get-ChildItem -Path @(
        "$env:USERPROFILE\.conda\envs\Pointcept",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    ) -Filter nvcc.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        return $found.Directory.Parent.FullName
    }
    return $null
}

function Ensure-Dirs {
    foreach ($d in @($SourceRoot, $DistRoot, $LogRoot)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}

function Write-Log {
    param([string]$Message, [string]$LogFile)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $line
    }
}
