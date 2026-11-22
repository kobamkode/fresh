alias ll="ls -al --color=auto"
alias tks="tmux kill-server"
alias t="tmux"
alias ta="tmux a"
alias lg="lazygit"
alias ld="lazydocker"
alias c="capture -t"
alias cn="capture"
alias cl="capture -l"
alias co="capture open"
alias clw="capture -l -w"

# --no-approve, like bootstrap.sh: otherwise a project-local .pi/settings.json
# turns the extension update into an approval prompt mid-run.
update() { sudo dnf -y upgrade && flatpak -y update && mise upgrade && pi update --extensions --no-approve; }

ytraw() {
    if [ $# -lt 1 ]; then
        echo "usage: ytraw <youtube-url> [dest.md]" >&2
        return 1
    fi
    local url=$1 dest=$2 id
    if [ -z "$dest" ]; then
        id=$(printf '%s\n' "$url" | sed -E 's#.*(v=|youtu\.be/|shorts/|embed/)([^&?/]+).*#\2#')
        [[ $id =~ ^[A-Za-z0-9_-]{11}$ ]] || id=video
        dest="raw/$(date +%Y-%m-%d)-$id.md"
    fi
    mkdir -p "$(dirname -- "$dest")"
    summarize "$url" --extract --format md >"$dest" && echo "wrote $dest"
}

# jpi <capture-id> [extra instruction...] — find a capture, then open it in pi.
# A function, not a script, so pi inherits this terminal and stays interactive.
jpi() {
    if [ $# -lt 1 ] || [ -z "$1" ]; then
        echo "usage: jpi <capture-id> [extra instruction...]" >&2
        return 2
    fi
    local id=${1,,} hit content instruction prompt
    shift

    if ! command -v capture >/dev/null 2>&1; then
        echo "jpi: 'capture' not found on PATH" >&2
        return 1
    fi
    if ! command -v pi >/dev/null 2>&1; then
        echo "jpi: 'pi' not found on PATH" >&2
        return 1
    fi

    # Older binaries treat 'find <id>' as text to append, which would write to
    # the journal. Refuse before that happens.
    if ! capture --help 2>/dev/null | grep -q 'find <id>'; then
        echo "jpi: capture is too old for 'find'; update with: go install github.com/kobamkode/capture@latest" >&2
        return 1
    fi

    hit=$(capture find "$id") || return $?
    if [ -z "$hit" ]; then
        echo "jpi: no capture $id" >&2
        return 1
    fi

    # capture prints "path:line:- [ ] | HH:MM | id | text": keep the text only.
    content=$(printf '%s\n' "$hit" | sed -E \
        -e 's/^[^:]*:[0-9]+://' \
        -e 's/^- (\[[ xX]\] \| )?([0-9]{2}:[0-9]{2} \| )?[0-9a-f]{7} \| //' \
        -e 's/[[:space:]]+$//')

    instruction=${*:-Explain this capture and what it was about.}
    # pi keeps this terminal because nothing here redirects its stdin/stdout.
    prompt="$content"$'\n\n'"$instruction"
    command pi "$prompt"
}
