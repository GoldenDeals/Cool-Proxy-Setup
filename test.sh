#!/bin/bash

set -euo pipefail

TEST_URL="https://ifconfig.me"
EXPORT=false
EXPORT_FILE=""

usage() {
    echo "Usage: $0 [--export [file]] <file1> [file2] ... [fileN]"
    echo "       $0 [--export [file]] <wildcard-pattern>"
    echo "       $0 [--export [file]] <file1> <wildcard-pattern> ..."
    echo ""
    echo "Options:"
    echo "  --export [file]    Export working proxies to SmartProxy format"
    echo "                     If file is not specified, output to stdout"
    echo ""
    echo "Examples:"
    echo "  $0 kz nl"
    echo "  $0 kz*"
    echo "  $0 *.txt"
    echo "  $0 kz nl*"
    echo "  $0 --export kz nl"
    echo "  $0 --export output.txt kz*"
    exit 1
}

ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --export)
            EXPORT=true
            shift
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                if [[ "$1" == "-" ]] || [[ "$1" == "stdout" ]]; then
                    EXPORT_FILE=""
                    shift
                elif [[ "$1" =~ \.(txt|out|log)$ ]] || [[ "$1" =~ / ]]; then
                    if [[ -f "$1" ]] && head -1 "$1" 2>/dev/null | grep -q "name;login;password;address"; then
                        EXPORT_FILE=""
                    else
                        EXPORT_FILE="$1"
                        shift
                    fi
                fi
            fi
            ;;
        --help|-h)
            usage
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#ARGS[@]} -eq 0 ]]; then
    usage
fi

shopt -s nullglob

FILES=()
for pattern in "${ARGS[@]}"; do
    if [[ -f "$pattern" ]]; then
        FILES+=("$pattern")
    else
        found=false
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                FILES+=("$file")
                found=true
            fi
        done
        if [[ "$found" == "false" ]]; then
            echo "Warning: No files found matching pattern '$pattern'" >&2
        fi
    fi
done

shopt -u nullglob

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "Error: No valid files found" >&2
    usage
fi

UNIQUE_FILES=()
for file in "${FILES[@]}"; do
    found=false
    for unique_file in "${UNIQUE_FILES[@]}"; do
        if [[ "$file" == "$unique_file" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" == "false" ]]; then
        UNIQUE_FILES+=("$file")
    fi
done

WORKING_PROXIES=()

for INPUT_FILE in "${UNIQUE_FILES[@]}"; do
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "Warning: File '$INPUT_FILE' not found, skipping" >&2
        continue
    fi
    
    if [[ "$EXPORT" != "true" ]]; then
        echo "Testing proxies from: $INPUT_FILE"
    fi
    
    while IFS=';' read -r name login password address || [[ -n "$name" ]]; do
        [[ "$name" == "name" ]] && continue
        [[ -z "$name" ]] && continue
        
        address=$(echo "$address" | xargs)
        ip=$(curl --silent --max-time 8 \
                  --proxy "$address" \
                  --proxy-user "$login:$password" \
                  "$TEST_URL" 2>/dev/null) || true
        
        if [[ -n "$ip" ]]; then
            if [[ "$EXPORT" != "true" ]]; then
                echo "  ✔ $name - Working ($ip)"
            fi
            
            address_clean="${address#http://}"
            address_clean="${address_clean#https://}"
            proxy_ip="${address_clean%%:*}"
            proxy_port="${address_clean##*:}"
            proxy_port=$(echo "$proxy_port" | xargs)
            
            WORKING_PROXIES+=("$proxy_ip:$proxy_port|$name|$login|$password")
        else
            if [[ "$EXPORT" != "true" ]]; then
                echo "  ✖ $name - Not Working"
            fi
        fi
    done < "$INPUT_FILE"
    
    if [[ "$EXPORT" != "true" ]]; then
        echo ""
    fi
done

if [[ "$EXPORT" == "true" ]]; then
    if [[ -n "$EXPORT_FILE" ]]; then
        exec > "$EXPORT_FILE"
    fi
    
    echo "[SmartProxy Servers]"
    echo ""
    
    for proxy in "${WORKING_PROXIES[@]}"; do
        IFS='|' read -r ip_port name login password <<< "$proxy"
        echo "$ip_port [HTTP] [$name] [$login] [$password]"
    done
fi

