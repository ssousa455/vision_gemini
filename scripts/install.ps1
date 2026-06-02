#!/usr/bin/env pwsh
# install.ps1 — installs opencode-vision-gemini plugin on Windows
# Usage:
#   iwr -useb https://raw.githubusercontent.com/ssousa455/vision_gemini/main/scripts/install.ps1 | iex
#   OR
#   .\install.ps1
#
# Prerequisites (checked at start):
#   - PowerShell 7+ (Core)
#   - git in PATH
#   - node 20+ in PATH
#   - opencode already installed (we only patch its config)

[CmdletBinding()]
param(
    [string]$Repo = "https://github.com/ssousa455/vision_gemini.git",
    [switch]$NoSmokeTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PLUGIN_DIR = Join-Path $HOME ".config\opencode\plugins\vision-gemini"
$CONFIG_PATH = Join-Path $HOME ".config\opencode\opencode.jsonc"
$ENV_PATH = Join-Path $HOME ".config\opencode\.env"

function Write-Step { param($msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2{ param($msg) Write-Host "    $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  opencode-vision-gemini installer" -ForegroundColor Cyan
Write-Host "  https://github.com/ssousa455/vision_gemini" -ForegroundColor DarkGray
Write-Host ""

# ── 1. Prerequisites ───────────────────────────────────────────────────────────
Write-Step "Checking prerequisites"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7+ is required (you have $($PSVersionTable.PSVersion)). Install: https://aka.ms/powershell"
}
Write-Ok "PowerShell $($PSVersionTable.PSVersion)"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git not found in PATH. Install: https://git-scm.com/download/win"
}
$gitVer = (& git --version) -replace "git version ", ""
Write-Ok "git $gitVer"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "node not found in PATH. Install Node 20+: https://nodejs.org"
}
$nodeRaw = (& node -v) -replace "^v", ""
$nodeMajor = 0
if ($nodeRaw -match "^(\d+)\.") { $nodeMajor = [int]$Matches[1] }
if ($nodeMajor -lt 20) {
    throw "Node 20+ is required (you have v$nodeRaw). Install: https://nodejs.org"
}
Write-Ok "node v$nodeRaw"

if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    Write-Warn2 "opencode not found in PATH — install it from https://opencode.ai first"
}

# ── 2. Clone or update ────────────────────────────────────────────────────────
Write-Step "Installing plugin files"
$configParent = Split-Path $CONFIG_PATH -Parent
if (-not (Test-Path $configParent)) {
    New-Item -ItemType Directory -Path $configParent -Force | Out-Null
}

if (Test-Path (Join-Path $PLUGIN_DIR ".git")) {
    Write-Ok "Plugin already installed — pulling latest"
    git -C $PLUGIN_DIR pull --ff-only
} elseif (Test-Path $PLUGIN_DIR) {
    throw "Directory exists but is not a git repo: $PLUGIN_DIR. Remove it manually and re-run."
} else {
    Write-Ok "Cloning $Repo"
    git clone $Repo $PLUGIN_DIR
}

# ── 3. Build plugin URI (Windows: file:///C:/...) ─────────────────────────────
$pluginUri = "file:///" + ($PLUGIN_DIR.TrimStart('\').TrimStart('/') -replace "\\", "/")
Write-Ok "Plugin URI: $pluginUri"

# ── 4. Patch opencode.jsonc ───────────────────────────────────────────────────
Write-Step "Patching opencode.jsonc"

# Write helper that avoids UTF-8 BOM (which breaks JSONC parsers)
function Save-Utf8NoBom {
    param([string]$Path, [string]$Content)
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Set-Content -Path $Path -Value $Content -Encoding utf8NoBOM
    } else {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($Path, $Content, $utf8)
    }
}

if (Test-Path $CONFIG_PATH) {
    $cfg = Get-Content $CONFIG_PATH -Raw

    if ($cfg -notmatch [regex]::Escape($pluginUri)) {
        $pattern = '("plugin"\s*:\s*\[)([^\]]*?)(\])'
        $replacement = "`$1`$2,`n    `"$pluginUri`"`$3"
        $newCfg = $cfg -replace $pattern, $replacement

        if ($newCfg -eq $cfg -and $cfg -notmatch '"plugin"\s*:') {
            $newCfg = $cfg -replace '(\})\s*$', ",`n  `"plugin`": [`"$pluginUri`"]`n}"
        }

        if ($newCfg -ne $cfg) {
            Save-Utf8NoBom -Path $CONFIG_PATH -Content $newCfg
            Write-Ok "Added plugin to $CONFIG_PATH"
        } else {
            Write-Warn2 "Config has 'plugin' key but it is not an array. Please edit manually."
            throw "Cannot auto-patch opencode.jsonc"
        }
    } else {
        Write-Ok "Plugin already listed in $CONFIG_PATH"
    }
} else {
    $minimal = "{`n  `"plugin`": [`"$pluginUri`"]`n}"
    Save-Utf8NoBom -Path $CONFIG_PATH -Content $minimal
    Write-Ok "Created $CONFIG_PATH"
}

# ── 5. GOOGLE_API_KEY ─────────────────────────────────────────────────────────
Write-Step "Configuring GOOGLE_API_KEY"
$envParent = Split-Path $ENV_PATH -Parent
if (-not (Test-Path $envParent)) {
    New-Item -ItemType Directory -Path $envParent -Force | Out-Null
}

$existingKey = $null
if (Test-Path $ENV_PATH) {
    foreach ($line in Get-Content $ENV_PATH) {
        if ($line -match '^\s*GOOGLE_API_KEY\s*=\s*(\S.*)$') {
            $existingKey = $Matches[1].Trim()
            break
        }
    }
}

if ($existingKey) {
    $preview = if ($existingKey.Length -gt 8) { $existingKey.Substring(0, 8) + "..." } else { "***" }
    Write-Ok "GOOGLE_API_KEY already set (starts with: $preview)"
    $overwrite = Read-Host "    Overwrite? (y/N)"
    if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
        Write-Ok "Keeping existing key"
    } else {
        $existingKey = $null
    }
}

if (-not $existingKey) {
    $secureKey = Read-Host "    Enter your Google API key (https://aistudio.google.com/app/apikey)" -AsSecureString
    if (-not $secureKey) { throw "No API key provided" }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if ($plainKey -notmatch '^AIza[0-9A-Za-z_-]{30,}$') {
        $confirm = Read-Host "    Key doesn't look like a Gemini key (no 'AIza' prefix). Continue anyway? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') { throw "Aborted" }
    }
    Add-Content -Path $ENV_PATH -Value "GOOGLE_API_KEY=$plainKey"
    Write-Ok "Saved GOOGLE_API_KEY to $ENV_PATH"
}

# ── 6. Smoke test ─────────────────────────────────────────────────────────────
if (-not $NoSmokeTest) {
    Write-Step "Running smoke test"
    Push-Location $PLUGIN_DIR
    try {
        $out = & node test/smoke.js 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Smoke test passed"
        } else {
            Write-Warn2 "Smoke test returned exit code $LASTEXITCODE — non-fatal"
        }
    } catch {
        Write-Warn2 "Smoke test failed — non-fatal. Run manually: cd '$PLUGIN_DIR'; node test/smoke.js"
    } finally {
        Pop-Location
    }
}

# ── 7. Done ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "==> Done!" -ForegroundColor Green
Write-Host "    Plugin installed at: $PLUGIN_DIR"
Write-Host "    Config patched at:   $CONFIG_PATH"
Write-Host "    API key saved at:    $ENV_PATH"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart OpenCode (close and reopen the terminal / TUI)" -ForegroundColor White
Write-Host "  2. Try it:" -ForegroundColor White
Write-Host "       opencode run 'describe this image' -f C:\path\to\image.png" -ForegroundColor White
Write-Host "  3. Or just paste an image into an OpenCode chat session." -ForegroundColor White
Write-Host ""
