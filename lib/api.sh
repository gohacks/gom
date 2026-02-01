# Gom - Go Manager
# Fetch and parse go.dev API

# Fetch available versions JSON (limited to ~2 recent versions)
fetch_versions_json() {
    curl -sL "$GOM_API_URL" 2>/dev/null
}

# Fetch HTML page and extract all available versions (many more than JSON)
# Returns: go1.26rc2, go1.25.6, go1.25.5, go1.24.12, ...
fetch_versions_from_html() {
    local html
    html=$(curl -sL "$GOM_DL_HTML_URL" 2>/dev/null)
    if [[ -z "$html" ]]; then
        return 1
    fi
    # Extract versions from headings (### go1.25.6) and download links (go1.25.6.linux-amd64.tar.gz)
    echo "$html" | grep -oE 'go1\.[0-9]+(\.[0-9]+|rc[0-9]+)' | sort -Vu
}

# Extract version list from JSON (with stable flag)
# Returns: go1.25.6 stable, go1.24.12 stable, ...
parse_versions_from_json() {
    local json="$1"

    if command -v jq &>/dev/null; then
        echo "$json" | jq -r '.[] | "\(.version) \(if .stable then "stable" else "rc" end)"' 2>/dev/null
    else
        echo "$json" | grep -oP '"version":\s*"go[0-9.]+"' | sed 's/.*"\(go[0-9.]*\)".*/\1/' | while read -r v; do
            echo "$v stable"
        done
    fi
}

# Filter versions for display: stable only (no RC), latest minor shows all patches,
# 5 older minors show only latest patch. Output: newest first.
# Input: parse_versions output (version stable per line)
# Output: filtered "version stable" lines
filter_versions_for_list() {
    awk '
    function get_minor(v,  n) {
        n = v
        sub(/^go1\./, "", n)
        if (n ~ /^[0-9]+\.[0-9]+/) { sub(/\.[0-9]+.*$/, "", n); return 0+n }
        return 0
    }
    $1 !~ /rc/ { n++; ver[n]=$1; st[n]=$2; m[n]=get_minor($1) }
    END {
        if (n==0) exit
        latest_minor = 0
        for (i=1; i<=n; i++) if (m[i] > latest_minor) latest_minor = m[i]
        for (mn=latest_minor-1; mn>=1 && (latest_minor-mn)<=5; mn--) {
            for (i=n; i>=1; i--) if (m[i]==mn) { keep[ver[i]]=1; break }
        }
        for (i=n; i>=1; i--) {
            if (m[i] == latest_minor || keep[ver[i]]) print ver[i], st[i]
        }
    }'
}

# Get all available versions - merges JSON (for stable flag) with HTML (for full list)
# Returns: go1.26rc2 rc, go1.25.6 stable, go1.24.12 stable, ...
parse_versions() {
    local json="$1"
    local html_versions
    local json_versions

    # Get full list from HTML (many more versions)
    html_versions=$(fetch_versions_from_html 2>/dev/null)
    if [[ -z "$html_versions" ]]; then
        # Fallback to JSON only
        parse_versions_from_json "$json"
        return
    fi

    # Get stable/rc info from JSON for versions that exist there
    json_versions=$(parse_versions_from_json "$json" 2>/dev/null)

    # Merge: for each HTML version, use JSON stable flag if available, else assume stable for x.y.z and rc for rc
    while read -r v; do
        local flag="stable"
        if [[ "$v" =~ rc ]]; then
            flag="rc"
        fi
        # Check if in JSON for accurate flag
        local json_flag
        json_flag=$(echo "$json_versions" | grep "^${v} " | awk '{print $2}')
        if [[ -n "$json_flag" ]]; then
            flag="$json_flag"
        fi
        echo "$v $flag"
    done <<< "$html_versions"
}

# Get download filename (archive, OS/arch)
# $1: version (go1.24.12)
# $2: JSON
# Returns: go1.24.12.linux-amd64.tar.gz or empty
get_download_filename() {
    local version="$1"
    local json="$2"
    local platform
    platform=$(get_platform)

    if command -v jq &>/dev/null; then
        echo "$json" | jq -r --arg v "$version" --arg p "$platform" \
            '.[] | select(.version == $v) | .files[] | select(.kind == "archive" and ((.os + "-" + .arch) == $p)) | .filename' 2>/dev/null | head -1
    else
        # Fallback: grep for filename containing version and platform
        echo "$json" | grep -o "\"filename\":[[:space:]]*\"${version}\.${platform}\.tar\.gz\"" | head -1 | grep -oP '"\K[^"]+'
    fi
}

# Get file SHA256
# $1: version
# $2: filename
# $3: JSON
get_sha256() {
    local version="$1"
    local filename="$2"
    local json="$3"

    if command -v jq &>/dev/null; then
        echo "$json" | jq -r --arg v "$version" --arg f "$filename" \
            '.[] | select(.version == $v) | .files[] | select(.filename == $f) | .sha256' 2>/dev/null | head -1
    else
        # Fallback: grep in file block (sha256 comes after filename)
        echo "$json" | grep -A5 "\"filename\":[[:space:]]*\"$filename\"" | grep -oP '"sha256":[[:space:]]*"\K[a-f0-9]+' | head -1
    fi
}
