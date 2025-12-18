# Filesystem

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# General

alias redo='sudo "$(fc -ln -1)"'

# Development

alias python='python3'
alias py='python'
alias pip='pip3'

# Applications

alias vi="vim -c 'startinsert'"
alias vim="vim -c 'startinsert'"

# Workflow

alias ignore='git status --ignored --untracked-files=all'
alias status='git status -sb'
alias log='git log --oneline --graph --decorate --all'
alias reset='git reset --mixed HEAD~1'

alias clone='git clone --recurse-submodules'
alias deploy='git add --all && git commit --allow-empty-message -m "" && git push'
alias release='git add --all && git commit --allow-empty-message --allow-empty -m "[skip ci]" 2>/dev/null || true && git push origin HEAD && git push origin HEAD:release && git commit --allow-empty-message -m "" && git push origin HEAD:release'

backport() {
  cur=$(git rev-parse --abbrev-ref HEAD) || return 1
  sha=$(git rev-parse HEAD) || return 1
  git fetch origin develop || return 1
  git switch --detach origin/develop || return 1
  git switch -c "$1" || return 1
  git cherry-pick "$sha" || return 1
  git push -u origin "$1" || return 1
  git switch "$cur"
}

# Functions

extract () {
   if [ -f "$1" ] ; then
       case "$1" in
           *.tar.bz2)   tar xvjf "$1"    ;;
           *.tar.gz)    tar xvzf "$1"    ;;
           *.bz2)       bunzip2 "$1"     ;;
           *.gz)        gunzip "$1"      ;;
           *.tar)       tar xvf "$1"     ;;
           *.tgz)       tar xvzf "$1"    ;;
           *.zip)       unzip "$1"       ;;
       esac
   fi
}

exe() {
  docker exec -it "$(docker ps -qf name=$1)" /bin/bash
}

c() {
  [ -z "$1" ] && { cd; return; }
  [ -d "$1" ] && { cd "$1"; return; } ||
  [ -f "$1" ] && file -b "$1" | grep -q -e "text" -e "empty" && { cat "$1"; return; } ||
  file "$1"
}

d() {
  mkdir -pv "$1" && cd "$1";
}

f() {
    case "$1" in
      /*) grep --color=auto -rni "$1" . ;;
       *) find . -iname "*${1:1}*" ;;
    esac
}

l() {
  command ls -lAhF --color=auto "$@";
}

j() {
  journalctl -xe --no-pager -u "$1" || journalctl -xe --no-pager
}

p() {
  [ -z "$1" ] && { ps aux; return $?; }
  local search
  search="[${1:0:1}]${1:1}"
  ps aux | grep --color=auto "$search"
}

s() {
  [ -z "$1" ] && { cd /etc/systemd/system; return $?; }
  case "$1" in start|stop|restart|reload|enable|disable|status|is-active|is-enabled|is-failed|mask|unmask|daemon-reload|reset-failed| \
    cat|show|edit|list-units|list-unit-files|list-dependencies|list-jobs)
      command systemctl "$@"; return $?;;
  esac
  systemctl cat "$1" && echo && systemctl status --no-pager "$1"
}

package() {
  local project
  project=$(basename "$PWD")
  local out="${project}.txt"
  rm -f -- "$out"

  if [ -d .git ]; then
    file_list=$(git ls-files --cached --others --exclude-standard)
  else
    file_list=$(find . -type f -not -path '*/.git/*' -not -name "$out")
  fi

  while IFS= read -r file; do
    if file --mime-type --brief "$file" | grep -q '^text/'; then
      printf "# %s\n\n" "$file"
      sed '' "$file"
      printf "\n---\n\n"
    fi
  done > "$out" <<< "$file_list"
}
