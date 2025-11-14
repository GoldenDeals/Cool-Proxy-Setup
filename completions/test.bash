# Bash completion for test.sh

_test_complete() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local lists_dir="${script_dir}/lists"

    case "$prev" in
        --export)
            COMPREPLY=($(compgen -f -- "$cur"))
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--export --help" -- "$cur"))
        return 0
    fi

    if [[ -d "$lists_dir" ]]; then
        local files=$(find "$lists_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null)
        COMPREPLY=($(compgen -W "$files" -- "$cur"))
        COMPREPLY+=($(compgen -f -- "$cur"))
    fi

    return 0
}

complete -F _test_complete test.sh
complete -F _test_complete ./test.sh

