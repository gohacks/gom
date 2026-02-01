# Gom - Go Manager

Go installation manager in Bash (SDKMAN style). Works without Go installed, on any Linux distro or macOS.

## Installation


### Remote 
```bash
curl -sSL https://raw.githubusercontent.com/gohacks/gom/main/install.sh | bash
```

### Or from project folder

```bash
bash install.sh
```

## Usage

```bash
gom                    # Show available commands
gom list               # List available versions from go.dev
gom list installed     # List installed versions
gom install latest     # Install latest stable version
gom install 1.24       # Install Go 1.24.x
gom use latest         # Set latest installed as default
gom use 1.24           # Set Go 1.24.x as default
gom current            # Show current default version
gom init               # Generate command to add to PATH
```

## Structure

- `~/.gom/versions/` - Installed versions (go1.24.12, go1.23.5, ...)
- `~/.gom/current` - Symlink to default version

## Dependencies

- `curl` - Download
- `tar` - Extraction
- `jq` (optional) - JSON parsing (fallback with grep/sed if not available)

## Platforms

- Linux (amd64, arm64, 386, armv6l)
- macOS (amd64, arm64)
