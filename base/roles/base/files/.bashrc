# Basic

alias ls='ls -lhA --group-directories-first'
alias python='python3'
alias py='python'
alias pip='pip3'

# Filesystem

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias mkdir='mkdir -pv'

alias redo='sudo "$(fc -ln -1)"'

# Applications

alias vi="vim -c 'startinsert'"
alias vim="vim -c 'startinsert'"

alias clone='git clone --recurse-submodules'
alias reset='git reset --mixed HEAD~1'
alias deploy='git add --all && git commit --allow-empty-message -m "" && git push'
alias release='git add --all && git commit --allow-empty-message --allow-empty -m "[skip ci]" 2>/dev/null || true && git push origin HEAD && git push origin HEAD:release && git commit --allow-empty-message -m "" && git push origin HEAD:release'

alias venv='python3 -m venv .venv && source .venv/bin/activate'

# Functions

share() { cp "$1" /share/ }

# History and Prompt

HISTCONTROL=ignoredups:erasedups
HISTSIZE=1000
HISTFILESIZE=2000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
HISTIGNORE="ls:bg:fg:history"

PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
PS1='[%n@%m %1~]$ '