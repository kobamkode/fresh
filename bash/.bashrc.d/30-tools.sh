# interactive tools; skipped in non-interactive login shells (see 10-options)
[[ $- == *i* ]] || return 0

command -v mise >/dev/null && eval "$(mise activate bash)"
[ -f /usr/share/fzf/shell/key-bindings.bash ] && source /usr/share/fzf/shell/key-bindings.bash
# Starship manages PROMPT_COMMAND, so initialize zoxide afterward to preserve its hook.
command -v starship >/dev/null && eval "$(starship init bash)"
command -v zoxide >/dev/null && eval "$(zoxide init bash --cmd cd)"

# auto-attach tmux in interactive shells, unless already inside it
[[ -z $TMUX ]] && command -v tmux >/dev/null && exec tmux new-session -A -s main
