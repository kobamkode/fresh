alias ll="ls -al --color=auto"
alias tks="tmux kill-server"
alias t="tmux"
alias ta="tmux a"
alias lg="lazygit"
alias ld="lazydocker"
alias c="capture"
alias cl="capture -l"
alias clw="capture -l -w"

update() { sudo dnf -y upgrade && flatpak -y update; }

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
