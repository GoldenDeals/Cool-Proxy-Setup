#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 <filename> [--dir <dir>] [--state <file>] [--silent] [--rand | --cycle | --name <name>] command ..."
    echo "       (default mode is --cycle, default directory is ./lists)"
    exit 1
}

show_help() {
    cat << EOF
Execute a command with proxy environment variables set from a proxy list file.

USAGE:
    $0 <filename> [OPTIONS] [--rand | --cycle | --name <name>] command [args...]

ARGUMENTS:
    filename              Proxy list file to read from (CSV format: name;login;password;address)

OPTIONS:
    -h, --help            Show this help message and exit
    --dir <directory>     Directory where proxy files are located (default: ./lists)
                          If --state is not provided, state file will be stored in this directory
    --state <path>        State file path (default: ./lists/.state)
                          If path is a directory, uses <directory>/.proxy-state
    --silent              Suppress "Using proxy: <name>" output message
    --no-valid            Skip proxy file validation (not recommended)

PROXY SELECTION MODES (mutually exclusive):
    --rand                Select a random proxy from the list
    --cycle               Cycle through proxies sequentially (default)
                          State is stored per file in the state file
    --name <name>         Select a specific proxy by name

ENVIRONMENT VARIABLES:
    The script sets the following environment variables for the command:
    - HTTP_PROXY
    - HTTPS_PROXY
    - ALL_PROXY
    - http_proxy
    - https_proxy
    - all_proxy
    
    Proxy authentication is embedded in the URL format:
    http://login:password@host:port

STATE FILE:
    The state file stores the last used proxy for each proxy file in the format:
    <filename>:<proxy_name>
    
    Each proxy file maintains its own state independently, allowing multiple
    proxy files to be used with separate cycle positions.

EXAMPLES:
    # Use default cycle mode
    $0 kz curl https://ifconfig.me
    
    # Use random proxy
    $0 kz --rand wget https://example.com
    
    # Select specific proxy
    $0 kz --name kz-2 python script.py
    
    # Use custom directory for proxy files
    $0 kz --dir /path/to/proxies echo "test"
    
    # Use custom state file location
    $0 kz --state /tmp/my-state curl https://ifconfig.me
    
    # Suppress proxy name output
    $0 kz --silent --rand curl https://ifconfig.me
    
    # Combine options
    $0 kz --dir /path/to/proxies --state /tmp/state --silent --cycle python script.py

PROXY FILE FORMAT:
    The proxy file should be in CSV format with semicolon separator:
    name;login;password;address
    
    Example:
    name;login;password;address
    proxy1;user1;pass1;http://1.2.3.4:8080
    proxy2;user2;pass2;http://5.6.7.8:8080

EOF
    exit 0
}

if [[ $# -eq 0 ]]; then
    usage
fi

if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
fi

if [[ $# -lt 2 ]]; then
    usage
fi

FILENAME="$1"
shift

SILENT=false
MODE="cycle"
PROXY_NAME=""
PROXY_DIR="${SCRIPT_DIR}/lists"
STATE_FILE_SET=false
NO_VALIDATE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        --dir)
            if [[ $# -lt 2 ]]; then
                echo "Error: --dir requires a directory path" >&2
                usage
            fi
            PROXY_DIR="$2"
            shift 2
            ;;
        --state)
            if [[ $# -lt 2 ]]; then
                echo "Error: --state requires a file or directory path" >&2
                usage
            fi
            STATE_FILE="$2"
            if [[ -d "$STATE_FILE" ]]; then
                STATE_FILE="${STATE_FILE}/.proxy-state"
            fi
            STATE_FILE_SET=true
            shift 2
            ;;
        --silent)
            SILENT=true
            shift
            ;;
        --no-valid)
            NO_VALIDATE=true
            shift
            ;;
        --rand)
            MODE="rand"
            shift
            ;;
        --cycle)
            MODE="cycle"
            shift
            ;;
        --name)
            if [[ $# -lt 2 ]]; then
                echo "Error: --name requires a proxy name" >&2
                usage
            fi
            MODE="name"
            PROXY_NAME="$2"
            shift 2
            ;;
        --*)
            echo "Error: Invalid option '$1'. Use --help for usage information" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

ORIGINAL_FILENAME="$FILENAME"
FILENAME="${PROXY_DIR}/${FILENAME}"

if [[ "$STATE_FILE_SET" != "true" ]]; then
    STATE_FILE="${PROXY_DIR}/.state"
fi

if [[ ! -f "$FILENAME" ]]; then
    echo "Error: File '$FILENAME' not found" >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Error: No command provided" >&2
    usage
fi

validate_proxy_address() {
    local address="$1"
    
    if [[ ! "$address" =~ ^https?:// ]]; then
        return 1
    fi
    
    local without_protocol="${address#http://}"
    without_protocol="${without_protocol#https://}"
    
    if [[ -z "$without_protocol" ]]; then
        return 1
    fi
    
    if [[ ! "$without_protocol" =~ ^[^:]+:[0-9]+ ]]; then
        return 1
    fi
    
    return 0
}

validate_proxies() {
    local file="$1"
    local line_num=0
    local names=()
    local errors=()
    
    while IFS=';' read -r name login password address || [[ -n "$name" ]]; do
        ((line_num++))
        [[ "$name" == "name" ]] && continue
        [[ -z "$name" ]] && continue
        
        name=$(echo "$name" | xargs)
        address=$(echo "$address" | xargs)
        
        if [[ -z "$name" ]]; then
            errors+=("Line $line_num: Proxy name is empty")
            continue
        fi
        
        if [[ -z "$address" ]]; then
            errors+=("Line $line_num ($name): Proxy address is empty")
            continue
        fi
        
        if ! validate_proxy_address "$address"; then
            errors+=("Line $line_num ($name): Invalid proxy address format '$address'. Expected format: http://host:port or https://host:port")
            continue
        fi
        
        local i=0
        for existing_name in "${names[@]}"; do
            if [[ "$existing_name" == "$name" ]]; then
                errors+=("Line $line_num ($name): Duplicate proxy name found")
                break
            fi
            ((i++))
        done
        
        names+=("$name")
    done < "$file"
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "Error: Proxy file validation failed:" >&2
        for error in "${errors[@]}"; do
            echo "  $error" >&2
        done
        return 1
    fi
    
    return 0
}

read_proxies() {
    local file="$1"
    local proxies=()
    
    while IFS=';' read -r name login password address || [[ -n "$name" ]]; do
        [[ "$name" == "name" ]] && continue
        [[ -z "$name" ]] && continue
        
        address=$(echo "$address" | xargs)
        if [[ -n "$address" ]]; then
            proxies+=("$name|$login|$password|$address")
        fi
    done < "$file"
    
    printf '%s\n' "${proxies[@]}"
}

update_state() {
    local filename="$1"
    local proxy_name="$2"
    
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${filename}:" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
    fi
    echo "${filename}:${proxy_name}" >> "$STATE_FILE"
}

select_proxy() {
    local mode="$1"
    local filename="$2"
    local proxy_name="$3"
    local proxies=("${@:4}")
    local count=${#proxies[@]}
    
    if [[ $count -eq 0 ]]; then
        echo "Error: No valid proxies found in file" >&2
        exit 1
    fi
    
    case "$mode" in
        rand)
            local index=$((RANDOM % count))
            local selected_proxy="${proxies[$index]}"
            local selected_name=$(echo "$selected_proxy" | cut -d'|' -f1)
            update_state "$filename" "$selected_name"
            echo "$selected_proxy"
            ;;
        cycle)
            local current_index=0
            local last_proxy_name=""
            
            if [[ -f "$STATE_FILE" ]]; then
                last_proxy_name=$(grep "^${filename}:" "$STATE_FILE" 2>/dev/null | cut -d':' -f2- || echo "")
            fi
            
            if [[ -n "$last_proxy_name" ]]; then
                local i=0
                for proxy in "${proxies[@]}"; do
                    local name=$(echo "$proxy" | cut -d'|' -f1)
                    if [[ "$name" == "$last_proxy_name" ]]; then
                        current_index=$((i + 1))
                        break
                    fi
                    ((i++))
                done
            fi
            
            if [[ $current_index -ge $count ]]; then
                current_index=0
            fi
            
            local selected_proxy="${proxies[$current_index]}"
            local selected_name=$(echo "$selected_proxy" | cut -d'|' -f1)
            update_state "$filename" "$selected_name"
            
            echo "$selected_proxy"
            ;;
        name)
            for proxy in "${proxies[@]}"; do
                local name=$(echo "$proxy" | cut -d'|' -f1)
                if [[ "$name" == "$proxy_name" ]]; then
                    update_state "$filename" "$proxy_name"
                    echo "$proxy"
                    return 0
                fi
            done
            echo "Error: Proxy '$proxy_name' not found" >&2
            exit 1
            ;;
    esac
}

if [[ "$NO_VALIDATE" != "true" ]]; then
    if ! validate_proxies "$FILENAME"; then
        exit 1
    fi
fi

proxies_array=($(read_proxies "$FILENAME"))
selected_proxy=$(select_proxy "$MODE" "$ORIGINAL_FILENAME" "$PROXY_NAME" "${proxies_array[@]}")

proxy_name=$(echo "$selected_proxy" | cut -d'|' -f1)
proxy_login=$(echo "$selected_proxy" | cut -d'|' -f2)
proxy_password=$(echo "$selected_proxy" | cut -d'|' -f3)
proxy_address=$(echo "$selected_proxy" | cut -d'|' -f4)

protocol=""
address_without_protocol=""

if [[ "$proxy_address" =~ ^https:// ]]; then
    protocol="https://"
    address_without_protocol="${proxy_address#https://}"
elif [[ "$proxy_address" =~ ^http:// ]]; then
    protocol="http://"
    address_without_protocol="${proxy_address#http://}"
else
    protocol="http://"
    address_without_protocol="$proxy_address"
fi

if [[ -n "$proxy_login" ]] && [[ -n "$proxy_password" ]]; then
    proxy_url="${protocol}${proxy_login}:${proxy_password}@${address_without_protocol}"
elif [[ -n "$proxy_login" ]]; then
    proxy_url="${protocol}${proxy_login}@${address_without_protocol}"
else
    proxy_url="${protocol}${address_without_protocol}"
fi

if [[ "$SILENT" != "true" ]]; then
    echo "Using proxy: $proxy_name"
fi

exec env \
    HTTP_PROXY="$proxy_url" \
    HTTPS_PROXY="$proxy_url" \
    ALL_PROXY="$proxy_url" \
    http_proxy="$proxy_url" \
    https_proxy="$proxy_url" \
    all_proxy="$proxy_url" \
    "$@"

