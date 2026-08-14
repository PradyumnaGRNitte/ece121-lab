# ============================================================
#  ECE121 C++ Lab - SETUP.  Run ONCE per lab PC.
#  Log in as the normal Student account. NO ADMIN RIGHTS NEEDED.
#
#  Right-click > Run with PowerShell.  If it refuses:
#     powershell -ExecutionPolicy Bypass -File .\ECE121-SETUP.ps1
#
#  The script looks for these files NEXT TO ITSELF first (pen drive).
#  If they are missing AND the PC has internet, it downloads them
#  from the GitHub release below.
#     winlibs*.zip    - portable GCC   (only if PC has no compiler)
#     *cpptools*.vsix - C/C++ extension (only if PC has no internet
#                       to reach the VS Code marketplace)
# ============================================================

$RepoBase = "https://github.com/PradyumnaGRNitte/ece121-lab/releases/latest/download"

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # makes downloads ~10x faster
$here   = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$report = @()
$fatal  = $false

function Say($t,$m,$c) { Write-Host ("[{0}] {1}" -f $t,$m) -ForegroundColor $c }
function OK($m)   { Say "OK  " $m Green;  $script:report += "OK   : $m" }
function WARN($m) { Say "WARN" $m Yellow; $script:report += "WARN : $m" }
function FAIL($m) { Say "FAIL" $m Red;    $script:report += "FAIL : $m"; $script:fatal = $true }

# Cache downloads here so a PC only ever fetches once
$cache = Join-Path $env:LOCALAPPDATA "ECE121-cache"
New-Item -ItemType Directory -Path $cache -Force | Out-Null

# Look beside the script, then in the cache, then download from GitHub
function Get-Asset($pattern, $remoteName) {
    $f = Get-ChildItem $here   -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }

    $f = Get-ChildItem $cache  -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { Write-Host "       using cached $($f.Name)" -ForegroundColor DarkGray; return $f.FullName }

    $dest = Join-Path $cache $remoteName
    Write-Host "       downloading $remoteName from GitHub..." -ForegroundColor DarkGray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "$RepoBase/$remoteName" -OutFile $dest -UseBasicParsing
        return $dest
    } catch {
        Write-Host "       download failed: $($_.Exception.Message)" -ForegroundColor DarkGray
        Remove-Item $dest -Force -ErrorAction SilentlyContinue
        return $null
    }
}

Write-Host "`n=== ECE121 Lab Setup - $env:COMPUTERNAME ===`n" -ForegroundColor Cyan


# ============================================================
#  STEP 1 - Find a C++ compiler
# ============================================================
$searchDirs = @(
    "$env:LOCALAPPDATA\mingw64\bin",
    "C:\msys64\ucrt64\bin",
    "C:\msys64\mingw64\bin",
    "C:\MinGW\bin",
    "C:\TDM-GCC-64\bin",
    "C:\mingw64\bin"
)
function Find-Gpp {
    # 1. Is g++ already working on this PC? (respects PATH, any install location)
    $c = Get-Command g++ -ErrorAction SilentlyContinue
    if ($c) { return (Split-Path $c.Source -Parent) }

    # 2. Not on PATH - look in the usual install locations
    foreach ($d in $script:searchDirs) { if (Test-Path (Join-Path $d "g++.exe")) { return $d } }
    return $null
}
$gccDir = Find-Gpp

if (-not $gccDir) {
    WARN "No compiler on this PC. Installing portable toolchain..."
    $zip = Get-Asset "winlibs*.zip" "winlibs.zip"

    if (-not $zip) {
        FAIL "No compiler, and winlibs.zip not found locally or on GitHub."
    } else {
        try {
            if (Test-Path "$env:LOCALAPPDATA\mingw64") {
                Remove-Item "$env:LOCALAPPDATA\mingw64" -Recurse -Force
            }
            Write-Host "       extracting - takes 1-2 minutes..." -ForegroundColor DarkGray
            Expand-Archive -Path $zip -DestinationPath $env:LOCALAPPDATA -Force
            $gccDir = Find-Gpp
            if ($gccDir) { OK "Portable compiler installed: $gccDir" }
            else         { FAIL "Extracted but g++.exe not found - wrong zip?" }
        } catch { FAIL "Extract failed: $($_.Exception.Message)" }
    }
} else {
    OK "Compiler found: $gccDir"
}


# ============================================================
#  STEP 2 - Persist on the user PATH
# ============================================================
if ($gccDir) {
    $up = [Environment]::GetEnvironmentVariable("Path","User"); if (-not $up) { $up = "" }
    if ($up -split ';' -contains $gccDir) {
        OK "Already on user PATH"
    } else {
        [Environment]::SetEnvironmentVariable("Path", ($up.TrimEnd(';')+";"+$gccDir).TrimStart(';'), "User")
        OK "Added to user PATH (permanent, no admin)"
    }
    $env:Path += ";$gccDir"
    OK ("Version: " + (& g++ --version 2>&1 | Select-Object -First 1))
}


# ============================================================
#  STEP 3 - VS Code + C/C++ extension
# ============================================================
$codeCmd = $null
foreach ($p in @(
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
    "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
    "${env:ProgramFiles(x86)}\Microsoft VS Code\bin\code.cmd"
)) { if (Test-Path $p) { $codeCmd = $p; break } }
if (-not $codeCmd) {
    $c = Get-Command code -ErrorAction SilentlyContinue
    if ($c) { $codeCmd = $c.Source }
}

if (-not $codeCmd) {
    FAIL "VS Code not installed. Technician must install it."
} else {
    OK "VS Code: $codeCmd"
    $ext = @(); try { $ext = & $codeCmd --list-extensions 2>$null } catch { }

    if ($ext -contains "ms-vscode.cpptools") {
        OK "C/C++ extension already installed"
    } else {
        WARN "C/C++ extension missing. Installing..."
        # try the marketplace first - smaller and always current
        $done = $false
        try {
            & $codeCmd --install-extension ms-vscode.cpptools --force 2>&1 | Out-Null
            $ext = & $codeCmd --list-extensions 2>$null
            if ($ext -contains "ms-vscode.cpptools") { OK "Installed from marketplace"; $done = $true }
        } catch { }

        if (-not $done) {
            $vsix = Get-Asset "*cpptools*.vsix" "cpptools-windows-x64.vsix"
            if ($vsix) {
                try {
                    & $codeCmd --install-extension $vsix --force 2>&1 | Out-Null
                    $ext = & $codeCmd --list-extensions 2>$null
                    if ($ext -contains "ms-vscode.cpptools") { OK "Installed from vsix"; $done = $true }
                } catch { }
            }
        }
        if (-not $done) { WARN "Extension not installed. Students can add it from the Extensions panel." }
    }
}


# ============================================================
#  STEP 4 - Work folder + settings
# ============================================================
$work = Join-Path $env:USERPROFILE "Documents\ECE121"
New-Item -ItemType Directory -Path (Join-Path $work ".vscode") -Force | Out-Null
$cp = if ($gccDir) { ($gccDir -replace '\\','/') + "/g++.exe" } else { "" }

@'
{
  "files.autoSave": "onFocusChange",
  "terminal.integrated.defaultProfile.windows": "PowerShell",
  "terminal.integrated.cwd": "${workspaceFolder}",
  "editor.tabSize": 4,
  "editor.guides.bracketPairs": "active",
  "C_Cpp.default.cppStandard": "c++17",
  "C_Cpp.default.compilerPath": "COMPILERPATH",
  "C_Cpp.default.intelliSenseMode": "windows-gcc-x64",
  "git.terminalAuthentication": false,
  "git.useIntegratedAskPass": false,
  "files.exclude": { "**/*.exe": true }
}
'@.Replace("COMPILERPATH", $cp) | Set-Content (Join-Path $work ".vscode\settings.json") -Encoding UTF8
OK "Work folder ready: $work"


# ============================================================
#  STEP 5 - Prove it works
# ============================================================
if ($gccDir) {
    Push-Location $work
    '#include <iostream>
int main(){ std::cout << "SETUP OK"; }' | Set-Content ".\_t.cpp" -Encoding ASCII
    & g++ -std=c++17 .\_t.cpp -o .\_t.exe 2>&1 | Out-Null
    if ((Test-Path ".\_t.exe") -and ((& .\_t.exe) -match "SETUP OK")) { OK "Compile + run test PASSED" }
    else { FAIL "Test program did not build" }
    Remove-Item ".\_t.cpp",".\_t.exe" -Force -ErrorAction SilentlyContinue
    Pop-Location
}


# ============================================================
#  STEP 6 - Summary
# ============================================================
$status = if ($fatal) { "NEEDS ATTENTION" } else { "READY" }
try {
    Add-Content -Path (Join-Path $here "setup-log.txt") `
        -Value ("{0}`t{1}`t{2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm"), $env:COMPUTERNAME, $status)
} catch { }

Write-Host ""
if ($fatal) {
    Write-Host "=== THIS PC NEEDS ATTENTION - note the PC number ===" -ForegroundColor Red
    $report | Where-Object { $_ -like "FAIL*" -or $_ -like "WARN*" } |
        ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
} else {
    Write-Host "=== THIS PC IS READY ===" -ForegroundColor Green
    Write-Host "    Close all VS Code windows, then reopen." -ForegroundColor Cyan
}
Write-Host ""
Read-Host "Press Enter to close"
