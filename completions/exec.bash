# Bash completion for exec.sh

_exec_complete() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local lists_dir="${script_dir}/lists"

    case "$prev" in
        --dir|--state)
            COMPREPLY=($(compgen -d -- "$cur"))
            return 0
            ;;
        --name)
            if [[ -d "$lists_dir" ]] && [[ -n "${words[1]}" ]]; then
                local proxy_file="${lists_dir}/${words[1]}"
                if [[ -f "$proxy_file" ]]; then
                    local names=$(awk -F';' 'NR>1 && $1!="" {print $1}' "$proxy_file" 2>/dev/null)
                    COMPREPLY=($(compgen -W "$names" -- "$cur"))
                fi
            fi
            return 0
            ;;
        exec.sh|./exec.sh|"${script_dir}/exec.sh")
            if [[ -d "$lists_dir" ]]; then
                local files=$(find "$lists_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null)
                COMPREPLY=($(compgen -W "$files" -- "$cur"))
            fi
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--help --dir --state --silent --rand --cycle --name --no-valid" -- "$cur"))
        return 0
    fi

    if [[ $cword -eq 1 ]]; then
        if [[ -d "$lists_dir" ]]; then
            local files=$(find "$lists_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null)
            COMPREPLY=($(compgen -W "$files" -- "$cur"))
        fi
    fi

    return 0
}

complete -F _exec_complete exec.sh
complete -F _exec_complete ./exec.sh

