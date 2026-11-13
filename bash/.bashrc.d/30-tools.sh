# interactive tools; skipped in non-interactive login shells (see 10-options)
[[ $- == *i* ]] || return 0

command -v mise >/dev/null && eval "$(mise activate bash)"
command -v zoxide >/dev/null && eval "$(zoxide init bash --cmd cd)"
[ -f /usr/share/fzf/shell/key-bindings.bash ] && source /usr/share/fzf/shell/key-bindings.bash
# starship goes last so the prompt sees the final environment
command -v starship >/dev/null && eval "$(starship init bash)"

# auto-attach tmux in interactive shells, unless already inside it
[[ -z $TMUX ]] && command -v tmux >/dev/null && exec tmux new-session -A -s main
