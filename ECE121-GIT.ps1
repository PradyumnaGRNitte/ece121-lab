# ============================================================
#  ECE121 - Git setup / cleanup for SHARED lab PCs
#  No admin rights needed.
#
#  START of session:
#     irm https://raw.githubusercontent.com/PradyumnaGRNitte/ece121-lab/main/ECE121-GIT.ps1 | iex
#
#  WIPE NOW (recommended before leaving):
#     $Cleanup=$true; irm <same URL> | iex
#
#  Even if you forget, credentials are auto-wiped after 2 hours
#  AND at the next logon.
#
#  WARNING: this PC is shared. Never tick "remember me" in any
#  GitHub popup. Never save a token to a file on this PC.
# ============================================================

param([switch]$Cleanup)
# allow  $Cleanup=$true; irm ... | iex
if (-not $Cleanup) {
    $g = Get-Variable -Name Cleanup -Scope Global -ErrorAction SilentlyContinue
    if ($g -and $g.Value -eq $true) { $Cleanup = $true }
}

$ErrorActionPreference = "Continue"
function OK($m)   { Write-Host "[OK  ] $m" -ForegroundColor Green }
function WARN($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function INFO($m) { Write-Host "       $m" -ForegroundColor DarkGray }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] Git is not installed on this PC." -ForegroundColor Red
    return
}


# ============================================================
#  CLEANUP MODE
# ============================================================
if ($Cleanup) {
    Write-Host "`n=== ECE121 Git CLEANUP ===`n" -ForegroundColor Cyan

    foreach ($t in @("git:https://github.com", "git:https://gist.github.com")) {
        cmdkey /delete:$t 2>&1 | Out-Null
    }
    OK "Windows Credential Manager cleared"

    try { "protocol=https`nhost=github.com`n" | git credential reject 2>$null } catch { }

    foreach ($f in @("$env:USERPROFILE\.git-credentials",
                     "$env:USERPROFILE\.gitconfig",
                     "$env:APPDATA\GitHub")) {
        if (Test-Path $f) {
            Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue
            OK "Removed $f"
        }
    }

    git config --global --unset-all user.name         2>$null
    git config --global --unset-all user.email        2>$null
    git config --global --unset-all credential.helper 2>$null
    OK "Global git identity cleared"

    # Repos with a token baked into the remote URL
    $work = Join-Path $env:USERPROFILE "Documents\ECE121"
    if (Test-Path $work) {
        $leaky = Get-ChildItem $work -Recurse -Directory -Filter ".git" -ErrorAction SilentlyContinue |
                 ForEach-Object {
                     $cfg = Join-Path $_.FullName "config"
                     if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern "@github\.com" -Quiet)) {
                         $_.Parent.FullName
                     }
                 }
        if ($leaky) {
            WARN "These folders have a token inside the remote URL:"
            $leaky | ForEach-Object { Write-Host "         $_" -ForegroundColor Yellow }
            INFO "Delete the folder, or: git remote set-url origin https://github.com/USER/REPO.git"
        }
    }

    # Remove our own scheduled tasks
    foreach ($t in @("ECE121-GitCleanup-Timer", "ECE121-GitCleanup-Logon")) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    }
    OK "Scheduled auto-cleanup tasks removed"

    Write-Host "`n=== DONE. Also sign out of GitHub in the browser. ===`n" -ForegroundColor Cyan
    return
}


# ============================================================
#  SETUP MODE
# ============================================================
Write-Host "`n=== ECE121 Git setup - SHARED PC ===`n" -ForegroundColor Cyan

# Did a previous student leave anything behind?
$stale = @()
if (Test-Path "$env:USERPROFILE\.git-credentials") { $stale += ".git-credentials file" }
$prev = git config --global user.name 2>$null
if ($prev) { $stale += "global identity: $prev" }
if ((cmdkey /list:git:https://github.com 2>&1) -notmatch "not found|cannot find") {
    $stale += "saved GitHub login in Credential Manager"
}
if ($stale.Count) {
    WARN "Previous user's data found on this PC:"
    $stale | ForEach-Object { Write-Host "         $_" -ForegroundColor Yellow }
    Remove-Item "$env:USERPROFILE\.git-credentials" -Force -ErrorAction SilentlyContinue
    git config --global --unset-all user.name  2>$null
    git config --global --unset-all user.email 2>$null
    cmdkey /delete:git:https://github.com 2>&1 | Out-Null
    OK "Previous user's credentials removed"
}

$name  = Read-Host "Your name (e.g. Asha Kumar)"
$email = Read-Host "Your GitHub email"


# ============================================================
#  Make sure we are inside a git repo - clone it if not
# ============================================================
if (-not (Test-Path ".git")) {
    Write-Host ""
    INFO "This folder is not linked to GitHub yet."
    $url = Read-Host "Paste your GitHub repo URL (or press Enter to skip)"

    if ($url) {
        $url = $url.Trim()
        if ($url -notmatch "^https://github\.com/") {
            WARN "That does not look like a GitHub URL. Skipping clone."
        }
        else {
            # strip any token someone pasted into the URL
            $url = $url -replace "://[^/@\s]+@github\.com", "://github.com"
            if ($url -notmatch "\.git$") { $url = $url + ".git" }
            $folder = [IO.Path]::GetFileNameWithoutExtension($url)

            if (Test-Path $folder) {
                OK "Folder '$folder' already exists here"
            } else {
                INFO "Cloning $folder ..."
                git clone $url 2>&1 | ForEach-Object { INFO $_ }
            }

            if (Test-Path (Join-Path $folder ".git")) {
                Set-Location $folder
                OK "Now inside: $((Get-Location).Path)"
            } else {
                WARN "Clone did not succeed. Check the URL and your internet."
            }
        }
    }
}

if (Test-Path ".git") {
    git config --local user.name  $name
    git config --local user.email $email
    git config --local credential.helper ""
    OK "Identity set for THIS FOLDER only: $name <$email>"

    # never let a token live in the remote URL
    $r = git config --local --get remote.origin.url 2>$null
    if ($r -and $r -match "://[^/@\s]+@github\.com") {
        git remote set-url origin ($r -replace "://[^/@\s]+@github\.com", "://github.com")
        WARN "Removed a token that was stored in the remote URL"
    }

    # keep compiled programs and junk out of git
    if (-not (Test-Path ".gitignore")) {
        @"
# compiled programs
*.exe
*.o
*.obj
*.out
a.exe
a.out

# debug files
*.pdb
*.ilk
*.stackdump

# editor / OS junk
.vscode/
Thumbs.db
desktop.ini
"@ | Set-Content ".gitignore" -Encoding ASCII
        OK "Created .gitignore (keeps .exe and junk out of GitHub)"
    }
    elseif (-not (Select-String -Path ".gitignore" -Pattern "\*\.exe" -Quiet)) {
        Add-Content ".gitignore" "`n*.exe`n*.o`n*.out"
        OK "Added *.exe to your existing .gitignore"
    }
} else {
    WARN "Not in a git repo - identity saved globally for now"
    git config --global user.name  $name
    git config --global user.email $email
}

git config --global credential.helper ""
OK "Credential storage DISABLED (nothing saved to this PC)"

Write-Host ""
INFO "When you push, git asks for username + password:"
INFO "  Username = your GitHub username"
INFO "  Password = your Personal Access Token (NOT your GitHub password)"
INFO "You type it every push. That is deliberate - nothing is stored."


# ============================================================
#  AUTO-CLEANUP - runs even if the student forgets
# ============================================================
$appDir = Join-Path $env:LOCALAPPDATA "ECE121"
New-Item -ItemType Directory -Path $appDir -Force | Out-Null
$cleanFile = Join-Path $appDir "git-cleanup.ps1"

# Self-contained, so it works with no network at cleanup time
@'
foreach ($t in @("git:https://github.com","git:https://gist.github.com")) {
    cmdkey /delete:$t 2>&1 | Out-Null
}
try { "protocol=https`nhost=github.com`n" | git credential reject 2>$null } catch { }
foreach ($f in @("$env:USERPROFILE\.git-credentials",
                 "$env:USERPROFILE\.gitconfig",
                 "$env:APPDATA\GitHub")) {
    Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue
}
git config --global --unset-all user.name         2>$null
git config --global --unset-all user.email        2>$null
git config --global --unset-all credential.helper 2>$null

# Strip tokens embedded in any repo remote URL under Documents
$work = Join-Path $env:USERPROFILE "Documents"
Get-ChildItem $work -Recurse -Directory -Filter ".git" -ErrorAction SilentlyContinue |
  ForEach-Object {
    $cfg = Join-Path $_.FullName "config"
    if (Test-Path $cfg) {
        $txt = Get-Content $cfg -Raw -ErrorAction SilentlyContinue
        if ($txt -match "://[^/@\s]+@github\.com") {
            ($txt -replace "://[^/@\s]+@github\.com", "://github.com") |
                Set-Content $cfg -Encoding ASCII -ErrorAction SilentlyContinue
        }
    }
  }

# Scrub tokens out of PowerShell command history
$hist = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
if (Test-Path $hist) {
    try {
        (Get-Content $hist -ErrorAction Stop) |
            Where-Object { $_ -notmatch "ghp_|github_pat_|gho_|ghs_|@github\.com" } |
            Set-Content $hist -Encoding UTF8 -ErrorAction Stop
    } catch { Remove-Item $hist -Force -ErrorAction SilentlyContinue }
}

Add-Content -Path "$env:LOCALAPPDATA\ECE121\cleanup-log.txt" `
            -Value ("{0} auto-cleanup ran" -f (Get-Date -Format "yyyy-MM-dd HH:mm")) `
            -ErrorAction SilentlyContinue
'@ | Set-Content $cleanFile -Encoding UTF8

$timerOK = $false
$logonOK = $false

# 1. Two hours from now - covers the end of this lab session
try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
              -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$cleanFile`""
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                        -DontStopIfGoingOnBatteries -StartWhenAvailable
    $when = (Get-Date).AddHours(2)
    Register-ScheduledTask -TaskName "ECE121-GitCleanup-Timer" -Force -ErrorAction Stop `
        -Action $action -Settings $set `
        -Trigger (New-ScheduledTaskTrigger -Once -At $when) | Out-Null
    OK ("Auto-cleanup scheduled for " + $when.ToString("HH:mm"))
    $timerOK = $true
}
catch { WARN "Timer cleanup could not be scheduled: $($_.Exception.Message)" }

# 2. At next logon - needs admin on most PCs, so failure here is normal
try {
    Register-ScheduledTask -TaskName "ECE121-GitCleanup-Logon" -Force -ErrorAction Stop `
        -Action $action -Settings $set `
        -Trigger (New-ScheduledTaskTrigger -AtLogOn) | Out-Null
    OK "Auto-cleanup also scheduled at next logon"
    $logonOK = $true
}
catch { INFO "(Logon-trigger cleanup needs admin rights - skipped, not a problem)" }

Write-Host ""
if ($timerOK) {
    WARN ("Credentials auto-wipe at " + (Get-Date).AddHours(2).ToString("HH:mm") + ".")
    if (-not $logonOK) {
        INFO "If you finish earlier, run the cleanup yourself - see below."
    }
} else {
    WARN "AUTO-CLEANUP IS NOT ACTIVE ON THIS PC."
    WARN "You MUST run the cleanup manually before you leave."
}
WARN "To wipe now:  `$Cleanup=`$true; irm <script URL> | iex"
Write-Host ""
