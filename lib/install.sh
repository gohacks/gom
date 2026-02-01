# Gom - Go Manager
# Go version installation logic
#
# Note: gom_use and gom_bootstrap are defined in utils.sh

# Install a Go version
# $1: version (go1.24.12 or latest)
gom_install() {
    local version_input="$1"
    local version json filename sha256 url tmpdir

    # Ensure directories exist
    mkdir -p "$GOM_VERSIONS"

    # Fetch JSON
    json=$(fetch_versions_json)
    if [[ -z "$json" ]]; then
        err "Could not fetch versions from go.dev"
        return 1
    fi

    # Resolve version (latest or partial)
    if [[ -z "$version_input" ]]; then
        version=$(echo "$json" | jq -r '.[0].version' 2>/dev/null || echo "$json" | grep -oP '"version":\s*"go[0-9.]+"' | head -1 | sed 's/.*"\(go[0-9.]*\)".*/\1/')
    else
        version=$(resolve_version "$version_input" "$json")
    fi

    if [[ -z "$version" ]]; then
        err "Version not found: $version_input"
        return 1
    fi

    # Already installed? Set as current and return
    if is_installed "$version"; then
        echo "gom: $version is already installed."
        rm -f "$GOM_CURRENT"
        ln -sf "$GOM_VERSIONS/$version" "$GOM_CURRENT"
        echo "gom: $version set as default version"
        if ! path_has_gom 2>/dev/null; then
            echo ""
            echo "Add to PATH:"
            echo "  eval \"\$(gom init)\""
        fi
        return 0
    fi

    # Get filename for download
    filename=$(get_download_filename "$version" "$json")
    if [[ -z "$filename" ]]; then
        err "No package found for $version on platform $(get_platform)"
        return 1
    fi

    sha256=$(get_sha256 "$version" "$filename" "$json")
    url="https://go.dev/dl/$filename"

    echo "gom: Downloading $version..."
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    if ! curl -sL -o "$tmpdir/$filename" "$url"; then
        err "Failed to download $url"
        return 1
    fi

    # Verify SHA256 if available
    if [[ -n "$sha256" ]] && command -v sha256sum &>/dev/null; then
        local actual
        actual=$(sha256sum "$tmpdir/$filename" | awk '{print $1}')
        if [[ "$actual" != "$sha256" ]]; then
            err "SHA256 verification failed for $filename"
            return 1
        fi
    fi

    echo "gom: Extracting $version..."
    mkdir -p "$GOM_VERSIONS/$version"
    if ! tar -xzf "$tmpdir/$filename" -C "$tmpdir"; then
        err "Failed to extract file"
        return 1
    fi

    # Tar extracts a "go" folder - move contents to versions/version/
    if [[ -d "$tmpdir/go" ]]; then
        mv "$tmpdir/go"/* "$GOM_VERSIONS/$version/"
        rmdir "$tmpdir/go" 2>/dev/null || true
    else
        # Some files may extract directly
        mv "$tmpdir"/* "$GOM_VERSIONS/$version/" 2>/dev/null || true
    fi

    echo "gom: $version installed at $GOM_VERSIONS/$version"

    # Automatically set as current
    rm -f "$GOM_CURRENT"
    ln -sf "$GOM_VERSIONS/$version" "$GOM_CURRENT"
    echo "gom: $version set as default version"
    if ! path_has_gom 2>/dev/null; then
        echo ""
        echo "Add to PATH:"
        echo "  eval \"\$(gom init)\""
    fi
}

# Bootstrap: prompt and install when no versions exist
gom_bootstrap() {
    echo ""
    echo "No version installed. Install latest stable? [Y/n] Or type desired version (e.g. 1.24):"
    read -r response

    response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

    if [[ -z "$response" ]] || [[ "$response" == "y" ]] || [[ "$response" == "yes" ]]; then
        gom_install "latest"
        if [[ $? -eq 0 ]]; then
            local latest
            latest=$(list_installed | sort -V | tail -1)
            gom_use "$latest"
        fi
    elif [[ "$response" == "n" ]] || [[ "$response" == "no" ]]; then
        echo "gom: No version installed."
        return 0
    else
        gom_install "$response"
        if [[ $? -eq 0 ]]; then
            local installed
            installed=$(resolve_version "$response" "" 2>/dev/null || echo "go$response")
            if [[ "$installed" =~ ^go ]]; then
                gom_use "$installed"
            else
                gom_use "$response"
            fi
        fi
    fi
}
