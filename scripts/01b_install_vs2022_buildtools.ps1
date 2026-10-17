#Requires -Version 5.1
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
Ensure-Dirs
$log = Join-Path $LogRoot "01b_install_vs2022.log"
"" | Set-Content -Path $log -Encoding utf8

function Find-Vs2022VcVars {
    $paths = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
    )
    foreach ($p in $paths) {
        if (Test-VsVcVars $p) { return $p }
    }
    # vswhere fallback
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $installPath = & $vswhere -products * -version "[17.0,18.0)" -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
        if ($installPath) {
            $candidate = Join-Path $installPath "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-VsVcVars $candidate) { return $candidate }
        }
    }
    return $null
}

$vcvars2022 = Find-Vs2022VcVars
if ($vcvars2022) {
    Write-Log "VS2022 C++ toolchain already present: $vcvars2022" $log
    # Show resolved cl for diagnostics
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    cmd /c "`"$vcvars2022`" >nul && where cl" 2>&1 | ForEach-Object {
        Write-Host $_
        Add-Content -Path $log -Value "$_"
    }
    $ErrorActionPreference = $prev
    exit 0
}

$installer = Join-Path $SourceRoot "vs_BuildTools.exe"
if (-not (Test-Path $installer)) {
    Write-Log "Downloading VS2022 Build Tools bootstrapper..." $log
    curl.exe -L --retry 3 -o $installer "https://aka.ms/vs/17/release/vs_BuildTools.exe"
}

Write-Log "Installing VS2022 VCTools (quiet). This can take 10-40+ minutes..." $log
$argList = @(
    "--quiet",
    "--wait",
    "--norestart",
    "--add", "Microsoft.VisualStudio.Workload.VCTools",
    "--includeRecommended",
    "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "--add", "Microsoft.VisualStudio.Component.Windows11SDK.22621"
)

$proc = Start-Process -FilePath $installer -ArgumentList $argList -Wait -PassThru -NoNewWindow
Write-Log "Installer exit code: $($proc.ExitCode)" $log

$vcvars2022 = Find-Vs2022VcVars
if (-not $vcvars2022) {
    throw @"
VS2022 C++ toolchain not detected.

Note: vcvars64.bat is normally only ~40 bytes (a wrapper). Detection now checks for Hostx64\x64\cl.exe.

Checked:
  C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\...
  and vswhere for VS 17.x with VC.Tools.

Open Visual Studio Installer -> Build Tools 2022 -> Modify -> enable
'Desktop development with C++' / MSVC v143, then re-run.
"@
}

Write-Log "VS2022 ready: $vcvars2022" $log
