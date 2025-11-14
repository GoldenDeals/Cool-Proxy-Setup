# Proxy List Manager

A simple bash script suite for managing and using proxy lists with automatic rotation and testing capabilities.

## Features

- **Proxy Execution**: Execute commands with proxy environment variables set
- **Proxy Testing**: Test multiple proxy files and wildcard patterns
- **Export**: Export working proxies to SmartProxy format
- **Multiple Selection Modes**: Cycle, random, or select by name
- **State Management**: Tracks last used proxy per file for cycling

## Installation

1. Clone or download this repository
2. Make scripts executable:
   ```bash
   chmod +x exec.sh test.sh
   ```

## Directory Structure

```
.proxy-list/
├── exec.sh          # Execute commands with proxies
├── test.sh          # Test proxy connectivity
├── lists/           # Proxy list files (default location)
│   ├── kz
│   ├── nl
│   └── ...
└── .state           # State file (auto-created)
```

## Proxy File Format

Proxy files should be in CSV format with semicolon separator:

```
name;login;password;address
proxy1;user1;pass1;http://1.2.3.4:8080
proxy2;user2;pass2;http://5.6.7.8:8080
```

## Usage

### exec.sh - Execute Commands with Proxy

Execute a command with proxy environment variables set from a proxy list file.

```bash
./exec.sh <filename> [OPTIONS] [--rand | --cycle | --name <name>] command [args...]
```

**Default behavior:**
- Directory: `./lists`
- Mode: `--cycle` (sequential rotation)
- State file: `./lists/.state`

**Examples:**
```bash
# Use default cycle mode
./exec.sh kz curl https://ifconfig.me

# Use random proxy
./exec.sh kz --rand wget https://example.com

# Select specific proxy
./exec.sh kz --name kz-2 python script.py

# Use custom directory
./exec.sh kz --dir /path/to/proxies echo "test"

# Suppress proxy name output
./exec.sh kz --silent --rand curl https://ifconfig.me
```

**Options:**
- `--dir <directory>` - Directory where proxy files are located (default: ./lists)
- `--state <path>` - State file path (default: ./lists/.state)
- `--silent` - Suppress "Using proxy: <name>" output
- `--rand` - Select a random proxy
- `--cycle` - Cycle through proxies sequentially (default)
- `--name <name>` - Select a specific proxy by name
- `--no-valid` - Skip proxy file validation

### test.sh - Test Proxy Connectivity

Test proxy files for connectivity and optionally export working proxies.

```bash
./test.sh [--export [file]] <file1> [file2] ... [fileN]
./test.sh [--export [file]] <wildcard-pattern>
```

**Examples:**
```bash
# Test single file
./test.sh kz

# Test multiple files
./test.sh kz nl

# Test with wildcards
./test.sh kz*
./test.sh *.txt

# Export working proxies to stdout
./test.sh --export kz nl

# Export to file
./test.sh --export output.txt kz*
```

**Options:**
- `--export [file]` - Export working proxies to SmartProxy format
  - If file is not specified, output to stdout
  - Files ending in .txt/.out/.log or containing / are treated as export files
  - Otherwise, treated as proxy files to test

## Shell Integration

### Zsh Integration

Add to your `~/.zshrc`:

```zsh
command_not_found_handler() {
    if [[ "$1" =~ ^p-([a-zA-Z0-9_-]+)$ ]]; then
        local proxy_file="${match[1]}"
        local proxy_dir="$HOME/.proxy-list"
        local proxy_path="$proxy_dir/lists/$proxy_file"
        
        if [[ -f "$proxy_path" ]]; then
            shift
            "$proxy_dir/exec.sh" "$proxy_file" "$@"
            return $?
        else
            echo "Error: Proxy file '$proxy_file' not found in $proxy_dir/lists" >&2
            return 1
        fi
    fi
    
    if (( $+functions[command_not_found_handler_original] )); then
        command_not_found_handler_original "$@"
    elif (( $+functions[_command_not_found_handler] )); then
        _command_not_found_handler "$@"
    else
        echo "zsh: command not found: $1" >&2
        return 127
    fi
}
```

After adding this, you can use proxies directly:
```bash
p-kz curl https://ifconfig.me
p-nl --rand wget https://example.com
```

### Bash/Zsh Completion

Source the completion files in your shell configuration:

**Bash:**
```bash
source ~/.proxy-list/completions/exec.bash
source ~/.proxy-list/completions/test.bash
```

**Zsh:**
```zsh
fpath=(~/.proxy-list/completions $fpath)
autoload -U compinit && compinit
```

## Environment Variables

When executing commands, the following environment variables are set:
- `HTTP_PROXY`
- `HTTPS_PROXY`
- `ALL_PROXY`
- `http_proxy`
- `https_proxy`
- `all_proxy`

Proxy authentication is embedded in the URL format: `http://login:password@host:port`

## State File

The state file stores the last used proxy for each proxy file in the format:
```
<filename>:<proxy_name>
```

Each proxy file maintains its own state independently, allowing multiple proxy files to be used with separate cycle positions.

## Export Format

When using `--export`, working proxies are exported in SmartProxy format:

```
[SmartProxy Servers]

10.0.10.0:2393 [HTTP] [kz-1] [auto] [Password]
94.21.23.22:2323 [HTTP] [kz-2] [auto] [Password]
```

## Testing

Run the test suite:
```bash
bats exec.bats
bats test_test.bats
```

