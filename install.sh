#!/usr/bin/env bash
# Gom - Go Manager installer
# Usage (local):  bash install.sh
# Usage (remote): curl -sSL https://raw.githubusercontent.com/gohacks/gom/main/install.sh | bash

set -e

GOM_INSTALL_DIR="${GOM_INSTALL_DIR:-$HOME/.local/bin}"
GOM_SHARE_DIR="${GOM_SHARE_DIR:-$HOME/.local/share/gom}"
GOM_REPO="${GOM_REPO:-https://github.com/gohacks/gom}"
GOM_BRANCH="${GOM_BRANCH:-main}"

echo "Gom - Go Manager"
echo ""
echo "Installing to: $GOM_INSTALL_DIR"
echo ""

# Detect install mode: local (from project dir) or remote (curl | bash)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
if [[ "$SCRIPT_SOURCE" == *"/dev/stdin"* ]] || [[ "$SCRIPT_SOURCE" == "-" ]] || [[ ! -d "$(dirname "$SCRIPT_SOURCE")/bin" ]]; then
    # Remote install: download from GitHub via curl (avoids git clone, often blocked)
    TMP_DIR=$(mktemp -d)
    trap "rm -rf '$TMP_DIR'" EXIT
    echo "Downloading gom..."
    curl -sSL "${GOM_REPO}/archive/refs/heads/${GOM_BRANCH}.tar.gz" | tar xz -C "$TMP_DIR" --strip-components=1
    SCRIPT_DIR="$TMP_DIR"
else
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi

mkdir -p "$GOM_INSTALL_DIR"
mkdir -p "$GOM_SHARE_DIR"

# Copy bin and lib to ~/.local/share/gom
cp -r "$SCRIPT_DIR/bin" "$GOM_SHARE_DIR/"
cp -r "$SCRIPT_DIR/lib" "$GOM_SHARE_DIR/"
chmod +x "$GOM_SHARE_DIR/bin/gom"

# Create wrapper in ~/.local/bin
cat > "$GOM_INSTALL_DIR/gom" << WRAPPER
#!/usr/bin/env bash
exec "$GOM_SHARE_DIR/bin/gom" "\$@"
WRAPPER
chmod +x "$GOM_INSTALL_DIR/gom"

# Try to add PATH to shell config (detect bash/zsh by checking files in home)
CONFIG_ADDED=false
GOM_SNIPPET="
# Gom - Go Manager
export PATH=\"$GOM_INSTALL_DIR:\$PATH\"
export PATH=\"\$HOME/.gom/current/bin:\$PATH\"
"

add_to_shell_config() {
    local file="$1"
    local create_if_missing="${2:-false}"
    [[ -z "$file" ]] && return 1
    if [[ ! -f "$file" ]]; then
        [[ "$create_if_missing" != "true" ]] && return 1
        touch "$file" 2>/dev/null || return 1
    fi
    [[ ! -w "$file" ]] && return 1
    grep -q "Gom - Go Manager" "$file" 2>/dev/null && return 0
    echo "$GOM_SNIPPET" >> "$file" 2>/dev/null || return 1
    echo "Configured: $file"
    return 0
}

# Add to existing shell config files
for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    add_to_shell_config "$f" false && CONFIG_ADDED=true || true
done

# If nothing exists, create the appropriate config (zsh: .zshrc, bash: .bash_profile on macOS, .bashrc on Linux)
if [[ "$CONFIG_ADDED" != "true" ]]; then
    if [[ "$SHELL" == *zsh* ]]; then
        add_to_shell_config "$HOME/.zshrc" true && CONFIG_ADDED=true || true
    else
        if [[ "$(uname -s)" == "Darwin" ]]; then
            add_to_shell_config "$HOME/.bash_profile" true && CONFIG_ADDED=true || true
        fi
        add_to_shell_config "$HOME/.bashrc" true && CONFIG_ADDED=true || true
    fi
fi

echo ""
echo "Gom installed successfully!"
echo ""

if [[ "$CONFIG_ADDED" == "true" ]]; then
    echo "Starting new shell to load PATH..."
    exec "${SHELL:-/bin/bash}" -l
else
    echo "Add to your shell config (.bashrc, .zshrc, or .bash_profile):"
    echo ""
    echo "  export PATH=\"$GOM_INSTALL_DIR:\$PATH\""
    echo "  export PATH=\"\$HOME/.gom/current/bin:\$PATH\""
    echo ""
    echo "Or run:  eval \"\$(${GOM_INSTALL_DIR}/gom init)\""
    echo ""
fi
