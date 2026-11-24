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

export RIG_ASK_ENGINE="agy"
