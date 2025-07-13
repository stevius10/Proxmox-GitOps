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

alias reset='git reset --mixed HEAD~1'
alias clone='git clone --recurse-submodules'
alias deploy='git add --all && git commit --allow-empty-message -m "" && git push'
alias release='git add --all && git commit --allow-empty-message --allow-empty -m "[skip ci]" 2>/dev/null || true && git push origin HEAD && git push origin HEAD:release && git commit --allow-empty-message -m "" && git push origin HEAD:release'
