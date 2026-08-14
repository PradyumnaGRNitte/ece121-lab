# ============================================================
#  ECE121 - Git setup / cleanup for SHARED lab PCs
#  No admin rights needed.
#
#  START of session:
#     irm https://raw.githubusercontent.com/PradyumnaGRNitte/ece121-lab/main/ECE121-GIT.ps1 | iex
#
#  WIPE NOW (before leaving):
#     $Cleanup=$true; irm <same URL> | iex
#
#  Even if you forget, credentials are auto-wiped after 2 hours.
#
#  WARNING: this PC is shared. Never tick "remember me" in any
#  GitHub popup. Never save a token to a file on this PC.
# ============================================================

param([switch]$Cleanup)
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

    # If we are inside a repo, drop the GitHub link so the next
    # person cannot push into it by accident
    if (Test-Path ".git") {
        git remote remove origin 2>$null
        git config --local --unset-all user.name  2>$null
        git config --local --unset-all user.email 2>$null
        OK "GitHub link removed from this folder"
    }

    # Scrub tokens out of PowerShell history
    $hist = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    if (Test-Path $hist) {
        try {
            (Get-Content $hist -ErrorAction Stop) |
                Where-Object { $_ -notmatch "ghp_|github_pat_|gho_|ghs_|@github\.com" } |
                Set-Content $hist -Encoding UTF8 -ErrorAction Stop
            OK "Token lines removed from PowerShell history"
        } catch { Remove-Item $hist -Force -ErrorAction SilentlyContinue }
    }

    Unregister-ScheduledTask -TaskName "ECE121-GitCleanup-Timer" `
        -Confirm:$false -ErrorAction SilentlyContinue

    Write-Host "`n=== DONE. Also sign out of GitHub in the browser. ===`n" -ForegroundColor Cyan
    return
}


# ============================================================
#  SETUP MODE
# ============================================================
Write-Host "`n=== ECE121 Git setup - SHARED PC ===`n" -ForegroundColor Cyan

# Wipe anything the previous user left behind
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
#  Repo link - always set fresh, never inherited
# ============================================================
if (Test-Path ".git") {

    # Show whose repo this folder is currently pointing at
    $old = git config --local --get remote.origin.url 2>$null
    if ($old) {
        $shown = $old -replace "://[^/@\s]+@github\.com", "://github.com"
        WARN "This folder is currently linked to:"
        Write-Host "         $shown" -ForegroundColor Yellow
        git remote remove origin 2>$null
        OK "Old link removed"
    }

    $url = Read-Host "Paste YOUR GitHub repo URL"
    $url = $url.Trim()

    if ($url -notmatch "^https://github\.com/") {
        WARN "That does not look like a GitHub URL. No link set."
        INFO "You can set it later with: git remote add origin <url>"
    }
    else {
        # strip a token if one was pasted inside the URL
        if ($url -match "://[^/@\s]+@github\.com") {
            $url = $url -replace "://[^/@\s]+@github\.com", "://github.com"
            WARN "Removed a token from the URL you pasted - never do that"
        }
        if ($url -notmatch "\.git$") { $url = $url + ".git" }
        git remote add origin $url 2>$null
        OK "Linked to $url"
    }
}
else {
    # No repo here yet - clone theirs
    INFO "This folder is not linked to GitHub yet."
    $url = Read-Host "Paste YOUR GitHub repo URL (or press Enter to skip)"

    if ($url) {
        $url = ($url.Trim()) -replace "://[^/@\s]+@github\.com", "://github.com"
        if ($url -notmatch "^https://github\.com/") {
            WARN "That does not look like a GitHub URL. Skipping clone."
        }
        else {
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


# ============================================================
#  Identity + safety settings
# ============================================================
if (Test-Path ".git") {
    git config --local user.name  $name
    git config --local user.email $email
    git config --local credential.helper ""
    OK "Identity set for THIS FOLDER only: $name <$email>"

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
        OK "Created .gitignore (keeps .exe out of GitHub)"
    }
    elseif (-not (Select-String -Path ".gitignore" -Pattern "\*\.exe" -Quiet)) {
        Add-Content ".gitignore" "`n*.exe`n*.o`n*.out"
        OK "Added *.exe to your existing .gitignore"
    }
}
else {
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
INFO "The token will NOT appear on screen as you paste. That is normal."


# ============================================================
#  Auto-cleanup, in case the student forgets
# ============================================================
$appDir = Join-Path $env:LOCALAPPDATA "ECE121"
New-Item -ItemType Directory -Path $appDir -Force | Out-Null
$cleanFile = Join-Path $appDir "git-cleanup.ps1"

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

try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
              -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$cleanFile`""
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                        -DontStopIfGoingOnBatteries -StartWhenAvailable
    $when = (Get-Date).AddHours(2)
    Register-ScheduledTask -TaskName "ECE121-GitCleanup-Timer" -Force -ErrorAction Stop `
        -Action $action -Settings $set `
        -Trigger (New-ScheduledTaskTrigger -Once -At $when) | Out-Null
    Write-Host ""
    WARN ("Credentials auto-wipe at " + $when.ToString("HH:mm") + ".")
}
catch {
    Write-Host ""
    WARN "AUTO-CLEANUP IS NOT ACTIVE ON THIS PC."
    WARN "You MUST run the cleanup yourself before you leave."
}

WARN "To wipe now:  `$Cleanup=`$true; irm <script URL> | iex"
Write-Host ""
