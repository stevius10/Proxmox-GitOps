# Filesystem

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# General

alias l='ls -lhA --group-directories-first'
alias grep='grep --color=auto'
alias mdir='mkdir -pv'

alias df='df -h'
alias free='free -h'
alias du='du -h'

alias journal='journalctl -xef --output=short-iso --no-pager'
alias redo='sudo "$(fc -ln -1)"'

# Development

alias python='python3'
alias py='python'
alias pip='pip3'

# Applications

alias vi="vim -c 'startinsert'"
alias vim="vim -c 'startinsert'"

# Workflow

alias clone='git clone --recurse-submodules'
alias reset='git reset --mixed HEAD~1'
alias deploy='git add --all && git commit --allow-empty-message -m "" && git push'
alias release='git add --all && git commit --allow-empty-message --allow-empty -m "[skip ci]" 2>/dev/null || true && git push origin HEAD && git push origin HEAD:release && git commit --allow-empty-message -m "" && git push origin HEAD:release'

# Functions
cdir() { mkdir "$1" && cd "$1"; }