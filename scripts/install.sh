#!/usr/bin/env bash
# install.sh — installs opencode-vision-gemini plugin on macOS/Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/ssousa455/vision_gemini/main/scripts/install.sh | bash

set -euo pipefail

REPO="https://github.com/ssousa455/vision_gemini.git"
PLUGIN_DIR="$HOME/.config/opencode/plugins/vision-gemini"
CONFIG_PATH="$HOME/.config/opencode/opencode.jsonc"
ENV_PATH="$HOME/.config/opencode/.env"

green() { printf "\033[32m%s\033[0m" "$1"; }
yellow() { printf "\033[33m%s\033[0m" "$1"; }
cyan() { printf "\033[36m%s\033[0m" "$1"; }
red() { printf "\033[31m%s\033[0m" "$1"; }

echo ""
cyan "==> "; echo "opencode-vision-gemini installer"
cyan "    "; echo "https://github.com/ssousa455/vision_gemini"
echo ""

# 1. Prerequisites
cyan "==> "; echo "Checking prerequisites"

if ! command -v git >/dev/null 2>&1; then
    red "Error: "; echo "git not found. Install: https://git-scm.com" >&2
    exit 1
fi
git_ver=$(git --version | awk '{print $3}')
green "    ok "; echo "git $git_ver"

if ! command -v node >/dev/null 2>&1; then
    red "Error: "; echo "node not found. Install Node 20+: https://nodejs.org" >&2
    exit 1
fi
node_ver=$(node -v | sed 's/^v//')
node_major=$(echo "$node_ver" | cut -d. -f1)
if [ "$node_major" -lt 20 ]; then
    red "Error: "; echo "Node 20+ is required (you have v$node_ver)" >&2
    exit 1
fi
green "    ok "; echo "node v$node_ver"

if ! command -v opencode >/dev/null 2>&1; then
    yellow "    warn "; echo "opencode not found in PATH — install it from https://opencode.ai first"
fi

# 2. Ensure config dir exists
mkdir -p "$(dirname "$CONFIG_PATH")"

# 3. Clone or update
cyan "==> "; echo "Installing plugin files"
if [ -d "$PLUGIN_DIR/.git" ]; then
    green "    ok "; echo "Plugin already installed — pulling latest"
    git -C "$PLUGIN_DIR" pull --ff-only
elif [ -d "$PLUGIN_DIR" ]; then
    red "Error: "; echo "Directory exists but is not a git repo: $PLUGIN_DIR" >&2
    exit 1
else
    green "    ok "; echo "Cloning $REPO"
    git clone "$REPO" "$PLUGIN_DIR"
fi

# 4. Plugin URI (Unix: file:///home/...)
PLUGIN_URI="file://$PLUGIN_DIR"
green "    ok "; echo "Plugin URI: $PLUGIN_URI"

# 5. Patch opencode.jsonc
cyan "==> "; echo "Patching opencode.jsonc"
if [ -f "$CONFIG_PATH" ]; then
    if ! grep -qF "$PLUGIN_URI" "$CONFIG_PATH"; then
        if command -v python3 >/dev/null 2>&1; then
            green "    ok "; echo "Adding plugin via python3 (preserves formatting)"
            PLUGIN_URI_SED=$(printf '%s' "$PLUGIN_URI" | sed 's/[\/&]/\\&/g')
            CONFIG_PATH="$CONFIG_PATH" PLUGIN_URI="$PLUGIN_URI" python3 -c "
import json, os
p = os.environ['CONFIG_PATH']
uri = os.environ['PLUGIN_URI']
with open(p) as f:
    cfg = json.load(f)
plugins = cfg.get('plugin', [])
if isinstance(plugins, list) and uri not in plugins:
    plugins.append(uri)
    cfg['plugin'] = plugins
    with open(p, 'w') as f:
        json.dump(cfg, f, indent=2)
"
        else
            yellow "    warn "; echo "python3 not found — using sed fallback (less safe)"
            if grep -q '"plugin"' "$CONFIG_PATH"; then
                sed -i "s|\"plugin\" *: *\\[\\(.*\\)\\]\"|\"plugin\": [\\1, \"$PLUGIN_URI\"]|" "$CONFIG_PATH"
            else
                sed -i "s|}|,  \"plugin\": [\"$PLUGIN_URI\"]\n}|" "$CONFIG_PATH"
            fi
        fi
    else
        green "    ok "; echo "Plugin already listed in $CONFIG_PATH"
    fi
else
    green "    ok "; echo "No config found — creating minimal $CONFIG_PATH"
    cat > "$CONFIG_PATH" <<EOF
{
  "plugin": ["$PLUGIN_URI"]
}
EOF
fi

# 6. GOOGLE_API_KEY
cyan "==> "; echo "Configuring GOOGLE_API_KEY"
mkdir -p "$(dirname "$ENV_PATH")"

existing_key=""
if [ -f "$ENV_PATH" ]; then
    existing_key=$(grep -E "^GOOGLE_API_KEY=" "$ENV_PATH" | head -1 | cut -d= -f2- | tr -d '"' || true)
fi

if [ -n "$existing_key" ]; then
    preview="${existing_key:0:8}..."
    yellow "    ok "; echo "GOOGLE_API_KEY already set (starts with: $preview)"
    read -r -p "    Overwrite? (y/N) " overwrite
    if [[ "$overwrite" =~ ^[Yy]$ ]]; then
        existing_key=""
    fi
fi

if [ -z "$existing_key" ]; then
    # Use /dev/tty so input is not echoed or stored in shell history
    if [ -t 0 ]; then
        read -r -s -p "    Enter your Google API key (https://aistudio.google.com/app/apikey): " key
        echo
    else
        read -r -s -p "    Enter your Google API key: " key < /dev/tty
        echo
    fi
    if [ -z "$key" ]; then
        red "Error: "; echo "No API key provided" >&2
        exit 1
    fi
    if [[ ! "$key" =~ ^AIza[0-9A-Za-z_-]{30,}$ ]]; then
        yellow "    warn "; echo "Key doesn't look like a Gemini key (no 'AIza' prefix)"
        read -r -p "    Continue anyway? (y/N) " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { red "Aborted"; exit 1; }
    fi
    echo "GOOGLE_API_KEY=$key" >> "$ENV_PATH"
    chmod 600 "$ENV_PATH" 2>/dev/null || true
    green "    ok "; echo "Saved GOOGLE_API_KEY to $ENV_PATH"
fi

# 7. Smoke test
cyan "==> "; echo "Running smoke test"
if (cd "$PLUGIN_DIR" && node test/smoke.js); then
    green "    ok "; echo "Smoke test passed"
else
    yellow "    warn "; echo "Smoke test failed — non-fatal. Run manually: cd '$PLUGIN_DIR'; node test/smoke.js"
fi

# 8. Done
echo ""
green "==> Done!"
echo "    Plugin installed at: $PLUGIN_DIR"
echo "    Config patched at:   $CONFIG_PATH"
echo "    API key saved at:    $ENV_PATH"
echo ""
cyan "Next steps:"
echo "  1. Restart OpenCode (close and reopen the terminal / TUI)"
echo "  2. Try it:"
echo "       opencode run 'describe this image' -f /path/to/image.png"
echo "  3. Or just paste an image into an OpenCode chat session."
echo ""
