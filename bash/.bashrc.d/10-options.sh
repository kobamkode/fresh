# ~/.bashrc is also sourced by ~/.bash_profile, so skip interactive-only
# settings in plain `bash -lc 'cmd'` runs.
[[ $- == *i* ]] || return 0

shopt -s autocd cdspell checkwinsize histappend
HISTSIZE=10000
HISTFILESIZE=20000
bind 'set completion-ignore-case on'
