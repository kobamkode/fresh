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
