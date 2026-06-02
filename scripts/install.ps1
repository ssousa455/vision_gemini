#!/usr/bin/env pwsh
# install.ps1 — installs opencode-vision-gemini plugin on Windows
# Usage: iwr -useb https://raw.githubusercontent.com/YOUR_USER/vison_gemini/main/scripts/install.ps1 | iex

$ErrorActionPreference = "Stop"

$REPO = "https://github.com/YOUR_USER/vison_gemini.git"
$PLUGIN_DIR = Join-Path $HOME ".config\opencode\plugins\vision-gemini"
$CONFIG_PATH = Join-Path $HOME ".config\opencode\opencode.jsonc"
$ENV_PATH = Join-Path $HOME ".config\opencode\.env"

Write-Host "==> opencode-vision-gemini installer" -ForegroundColor Cyan

# 1. Check prerequisites
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is not installed. Install from https://git-scm.com/download/win"
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js is not installed. Install Node 20+ from https://nodejs.org"
}
$nodeVer = (node -v) -replace "v", "" -split "\." | Select-Object -First 1
if ([int]$nodeVer -lt 20) {
    Write-Error "Node 20+ is required (you have v$nodeVer)"
}

# 2. Ensure config dir exists
$configDir = Split-Path $CONFIG_PATH -Parent
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

# 3. Clone or update plugin
if (Test-Path $PLUGIN_DIR) {
    Write-Host "==> Plugin already installed at $PLUGIN_DIR — pulling latest" -ForegroundColor Yellow
    git -C $PLUGIN_DIR pull --ff-only
} else {
    Write-Host "==> Cloning $REPO to $PLUGIN_DIR" -ForegroundColor Cyan
    git clone $REPO $PLUGIN_DIR
}

# 4. Resolve plugin URI for this OS
$pluginUri = "file:///" + ($PLUGIN_DIR -replace "\\", "/")
Write-Host "==> Plugin URI: $pluginUri" -ForegroundColor Green

# 5. Patch opencode.jsonc
if (Test-Path $CONFIG_PATH) {
    $cfg = Get-Content $CONFIG_PATH -Raw
    if ($cfg -notmatch [regex]::Escape($pluginUri)) {
        Write-Host "==> Adding plugin to opencode.jsonc" -ForegroundColor Cyan
        $cfg = $cfg -replace '("plugin"\s*:\s*\[)([^\]]*?)(\])', "`$1`$2,`n    `"$pluginUri`"`$3"
        Set-Content -Path $CONFIG_PATH -Value $cfg -Encoding UTF8
    } else {
        Write-Host "==> Plugin already in opencode.jsonc" -ForegroundColor Yellow
    }
} else {
    Write-Host "==> No opencode.jsonc found — creating minimal one" -ForegroundColor Yellow
    @"
{
  "plugin": ["$pluginUri"]
}
"@ | Set-Content -Path $CONFIG_PATH -Encoding UTF8
}

# 6. Set GOOGLE_API_KEY
if (Test-Path $ENV_PATH) {
    $envContent = Get-Content $ENV_PATH -Raw
    if ($envContent -match "GOOGLE_API_KEY\s*=") {
        Write-Host "==> GOOGLE_API_KEY already set in $ENV_PATH" -ForegroundColor Yellow
        $existing = ($envContent | Select-String "GOOGLE_API_KEY\s*=\s*(\S+)").Matches[0].Groups[1].Value
        Write-Host "    Current value: $($existing.Substring(0, [Math]::Min(8, $existing.Length)))..." -ForegroundColor Gray
    } else {
        $key = Read-Host "==> Enter your Google API key (https://aistudio.google.com/app/apikey)"
        Add-Content -Path $ENV_PATH -Value "`nGOOGLE_API_KEY=$key"
    }
} else {
    $key = Read-Host "==> Enter your Google API key (https://aistudio.google.com/app/apikey)"
    "GOOGLE_API_KEY=$key" | Set-Content -Path $ENV_PATH -Encoding UTF8
}

# 7. Run smoke test
Write-Host "==> Running smoke test" -ForegroundColor Cyan
Push-Location $PLUGIN_DIR
try { node test/smoke.js } catch { Write-Warning "Smoke test failed (this is non-fatal)" }
Pop-Location

Write-Host ""
Write-Host "==> Done!" -ForegroundColor Green
Write-Host "    Plugin installed at: $PLUGIN_DIR"
Write-Host "    Config patched at:   $CONFIG_PATH"
Write-Host "    API key saved at:    $ENV_PATH"
Write-Host ""
Write-Host "Try it:" -ForegroundColor Cyan
Write-Host "  opencode run 'describe this image' -f C:\path\to\image.png" -ForegroundColor White
