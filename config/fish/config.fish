# paths
fish_add_path $HOME/.local/bin
fish_add_path $HOME/.opencode/bin
fish_add_path $HOME/go/bin

# tools
type -q mise; and mise activate fish | source
type -q zoxide; and zoxide init fish --cmd cd | source
test -f /usr/share/fzf/shell/key-bindings.fish; and source /usr/share/fzf/shell/key-bindings.fish

set -gx EDITOR nvim

# capture: requires CAPTURE_VAULT (vault root); optional CAPTURE_DAILY_DIR, CAPTURE_DAILY_FORMAT
set -gx CAPTURE_VAULT $HOME/dev/journal
set -gx CAPTURE_DAILY_DIR daily

alias wm="workmux"
alias ll="ls -al --color=auto"
alias tks="tmux kill-server"
alias t="tmux"
alias ta="tmux a"
alias lg="lazygit"
alias ld="lazydocker"
alias update="sudo dnf -y update && flatpak -y update"
