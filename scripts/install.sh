#!/usr/bin/env bash
# install.sh — installs opencode-vision-gemini plugin on macOS/Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_USER/vison_gemini/main/scripts/install.sh | bash

set -euo pipefail

REPO="https://github.com/YOUR_USER/vison_gemini.git"
PLUGIN_DIR="$HOME/.config/opencode/plugins/vision-gemini"
CONFIG_PATH="$HOME/.config/opencode/opencode.jsonc"
ENV_PATH="$HOME/.config/opencode/.env"

echo -e "\033[36m==> opencode-vision-gemini installer\033[0m"

# 1. Check prerequisites
for cmd in git node; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is not installed" >&2
        exit 1
    fi
done
node_major=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$node_major" -lt 20 ]; then
    echo "Error: Node 20+ is required (you have v$node_major)" >&2
    exit 1
fi

# 2. Ensure config dir exists
mkdir -p "$(dirname "$CONFIG_PATH")"

# 3. Clone or update plugin
if [ -d "$PLUGIN_DIR" ]; then
    echo -e "\033[33m==> Plugin already installed — pulling latest\033[0m"
    git -C "$PLUGIN_DIR" pull --ff-only
else
    echo -e "\033[36m==> Cloning $REPO to $PLUGIN_DIR\033[0m"
    git clone "$REPO" "$PLUGIN_DIR"
fi

# 4. Resolve plugin URI
PLUGIN_URI="file://$PLUGIN_DIR"
echo -e "\033[32m==> Plugin URI: $PLUGIN_URI\033[0m"

# 5. Patch opencode.jsonc
if [ -f "$CONFIG_PATH" ]; then
    if ! grep -qF "$PLUGIN_URI" "$CONFIG_PATH"; then
        echo -e "\033[36m==> Adding plugin to opencode.jsonc\033[0m"
        # Use python for safe JSON editing
        python3 -c "
import json, sys
p = '$CONFIG_PATH'
with open(p) as f:
    cfg = json.load(f)
plugins = cfg.get('plugin', [])
if '$PLUGIN_URI' not in plugins:
    plugins.append('$PLUGIN_URI')
cfg['plugin'] = plugins
with open(p, 'w') as f:
    json.dump(cfg, f, indent=2)
"
    else
        echo -e "\033[33m==> Plugin already in opencode.jsonc\033[0m"
    fi
else
    echo -e "\033[33m==> No opencode.jsonc found — creating minimal one\033[0m"
    cat > "$CONFIG_PATH" <<EOF
{
  "plugin": ["$PLUGIN_URI"]
}
EOF
fi

# 6. Set GOOGLE_API_KEY
mkdir -p "$(dirname "$ENV_PATH")"
if [ -f "$ENV_PATH" ] && grep -q "^GOOGLE_API_KEY=" "$ENV_PATH"; then
    echo -e "\033[33m==> GOOGLE_API_KEY already set in $ENV_PATH\033[0m"
else
    read -rsp "==> Enter your Google API key (https://aistudio.google.com/app/apikey): " key
    echo
    echo "GOOGLE_API_KEY=$key" >> "$ENV_PATH"
    chmod 600 "$ENV_PATH"
fi

# 7. Run smoke test
echo -e "\033[36m==> Running smoke test\033[0m"
(cd "$PLUGIN_DIR" && node test/smoke.js) || echo "Smoke test failed (non-fatal)"

echo ""
echo -e "\033[32m==> Done!\033[0m"
echo "    Plugin installed at: $PLUGIN_DIR"
echo "    Config patched at:   $CONFIG_PATH"
echo "    API key saved at:    $ENV_PATH"
echo ""
echo -e "\033[36mTry it:\033[0m"
echo "  opencode run 'describe this image' -f /path/to/image.png"
