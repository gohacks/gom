# Gom - Go Manager
# Utility functions: OS/arch, version resolution

# Detect OS and arch for download
# Retorna: linux-amd64, darwin-arm64, etc.
get_platform() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv6l|armv7l) arch="armv6l" ;;
        i386|i686) arch="386" ;;
        *) arch="$arch" ;;
    esac

    echo "${os}-${arch}"
}

# Resolve path to absolute, following symlinks (portable: Linux + macOS)
resolve_symlink() {
    local path="$1"
    [[ -z "$path" ]] && return 1
    if readlink -f / >/dev/null 2>&1; then
        readlink -f "$path"
        return $?
    fi
    # macOS/BSD: follow symlinks manually
    while [[ -L "$path" ]]; do
        local dir base
        dir=$(dirname "$path")
        base=$(readlink "$path")
        if [[ "$base" == /* ]]; then
            path="$base"
        else
            path=$(cd "$dir" 2>/dev/null && pwd)/$base
        fi
    done
    if [[ -d "$path" ]]; then
        (cd "$path" 2>/dev/null && pwd)
    else
        echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
    fi
}

# Normalize version: 1.24 -> go1.24.12, latest -> go1.25.6 (first stable)
# $1: partial version or "latest"
# $2: go.dev JSON (optional, for resolving latest)
resolve_version() {
    local input="$1"
    local json="${2:-}"

    if [[ -z "$input" ]]; then
        return 1
    fi

    # latest: find first stable in JSON
    if [[ "$input" == "latest" ]]; then
        if [[ -n "$json" ]]; then
            # Extract first version with stable: true
            if command -v jq &>/dev/null; then
                echo "$json" | jq -r '.[] | select(.stable == true) | .version' | head -1
            else
                # Fallback: get first version from JSON
                echo "$json" | grep -oP '"version":\s*"\Kgo[0-9.]+' | head -1
            fi
        else
            return 1
        fi
        return 0
    fi

    # Already in go1.24.12 format
    if [[ "$input" =~ ^go[0-9] ]]; then
        echo "$input"
        return 0
    fi

    # Partial format: 1.24 -> go1.24.x (latest)
    if [[ "$input" =~ ^[0-9]+\.[0-9]+ ]]; then
        # If we have JSON, find the latest that matches
        if [[ -n "$json" ]]; then
            if command -v jq &>/dev/null; then
                local match
                match=$(echo "$json" | jq -r --arg v "go${input}" '.[] | select(.version | startswith($v)) | .version' | head -1)
                if [[ -n "$match" ]]; then
                    echo "$match"
                    return 0
                fi
            fi
        fi
        # Fallback: search in installed
        if [[ -d "$GOM_VERSIONS" ]]; then
            local found
            found=$(ls -1 "$GOM_VERSIONS" 2>/dev/null | grep "^go${input}\." | sort -V | tail -1)
            if [[ -n "$found" ]]; then
                echo "$found"
                return 0
            fi
        fi
        # Not found - return go1.24 for install to try
        echo "go${input}"
        return 0
    fi

    echo "$input"
    return 0
}

# List installed versions
list_installed() {
    if [[ ! -d "$GOM_VERSIONS" ]]; then
        return 0
    fi
    ls -1 "$GOM_VERSIONS" 2>/dev/null | grep "^go" | sort -V
}

# Check if ~/.gom/current/bin is in PATH
path_has_gom() {
    local gom_bin="${GOM_CURRENT:-$HOME/.gom/current}/bin"
    [[ ":$PATH:" == *":$gom_bin:"* ]]
}

# Check if version is installed
is_installed() {
    local version="$1"
    [[ -d "$GOM_VERSIONS/$version" ]]
}

# Set default version (creates current symlink)
# $1: version (go1.24.12 or partial)
gom_use() {
    local version_input="$1"
    local version

    if [[ -z "$version_input" ]]; then
        err "Usage: gom use <version>"
        return 1
    fi

    # If no versions installed, redirect to bootstrap
    if ! list_installed | grep -q .; then
        gom_bootstrap
        return $?
    fi

    version=$(resolve_version "$version_input" "")
    if [[ -z "$version" ]]; then
        version="$version_input"
    fi

    # For "latest", use the most recently installed
    if [[ "$version_input" == "latest" ]]; then
        version=$(list_installed | sort -V | tail -1)
    fi

    if ! is_installed "$version"; then
        err "Version $version is not installed."
        echo "Run: gom install $version"
        return 1
    fi

    rm -f "$GOM_CURRENT"
    ln -sf "$GOM_VERSIONS/$version" "$GOM_CURRENT"
    echo "gom: using $version"
    if ! path_has_gom; then
        echo ""
        echo "Add to PATH:"
        echo "  export PATH=\"\$HOME/.gom/current/bin:\$PATH\""
        echo ""
        echo "Or run: eval \"\$(gom init)\""
    fi
}
