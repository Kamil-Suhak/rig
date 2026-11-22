# Personal workspace Zsh profile overrides (EndeavourOS)

export EDITOR=micro
export VISUAL=micro

_rig_prepend_path "$HOME/.pub-cache/bin"
_rig_prepend_path "$HOME/fvm/default/bin"

# @cmd: jbl — Connect to JBL headphones via Bluetooth (pass -d to disconnect)
jbl() {
    local mac="34:51:6F:32:A5:BC"
    if [[ "${1:-}" == "-d" || "${1:-}" == "--disconnect" ]]; then
        bluetoothctl disconnect "$mac"
    else
        bluetoothctl power on >/dev/null 2>&1
        bluetoothctl connect "$mac"
    fi
}

# @cmd: md — Fuzzy-find a Markdown file and render it with mdcat
md() {
    local dir="${1:-.}"
    local file
    file="$(find "$dir" -type f -name '*.md' 2>/dev/null | fzf --preview 'mdcat --columns=80 {}' --preview-window=right:60%:wrap)" || return 0
    [ -n "$file" ] && mdcat "$file"
}

# @cmd: ask — Ask Gemini via isolated streamed agy session (--ctx, --high, --local, -r, --keep-history)
ask() {
    case "${1:-}" in
        -h|--help|-Help)
            cat <<'EOF'
Usage: ask [--ctx [<sel>]] [--high] [--local] [-r|--reply] [-c|--continue] [--keep-history] <question>

Query Antigravity CLI ('agy') in an isolated ask-home with streamed response.
Accepts piped input (e.g. 'out | ask "why did this fail?"').
Options:
  --ctx              Include terminal command/output slice (default @1; pass 2, @2, or 3..2 before question)
  --high             Use high-reasoning model (gemini-4-hydrogen-high)
  --local            Run in current working directory (picks up repo-local GEMINI.md/AGENTS.md)
  -r, --reply        Send a follow-up prompt to the most recent ask conversation (inherits its cwd)
  -c, --continue     Open interactive agy TUI on the most recent ask conversation (inherits its cwd)
  --keep-history     Save conversation in main ~/.gemini/antigravity-cli instead of ask-home
  -h, --help         Show this help
EOF
            return 0
            ;;
    esac

    local last_cmd=""
    if command -v _rig_last_history_command >/dev/null 2>&1; then
        last_cmd="$(_rig_last_history_command)"
    fi

    if [ -n "$last_cmd" ]; then
        "${RIG_PYTHON:-python3}" "$RIG_ROOT/configs/bin/ask-helper" run --engine agy --fallback-command "$last_cmd" "$@"
    else
        "${RIG_PYTHON:-python3}" "$RIG_ROOT/configs/bin/ask-helper" run --engine agy "$@"
    fi
}
