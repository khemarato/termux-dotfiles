function prompt {
  local BLACK="\[\033[0;30m\]"
  local BLACKBOLD="\[\033[1;30m\]"
  local RED="\[\033[0;31m\]"
  local REDBOLD="\[\033[1;31m\]"
  local GREEN="\[\033[0;32m\]"
  local GREENBOLD="\[\033[1;32m\]"
  local YELLOW="\[\033[0;33m\]"
  local YELLOWBOLD="\[\033[1;33m\]"
  local BLUE="\[\033[0;34m\]"
  local BLUEBOLD="\[\033[1;34m\]"
  local PURPLE="\[\033[0;35m\]"
  local PURPLEBOLD="\[\033[1;35m\]"
  local CYAN="\[\033[0;36m\]"
  local CYANBOLD="\[\033[1;36m\]"
  local WHITE="\[\033[0;37m\]"
  local WHITEBOLD="\[\033[1;37m\]"
  local RESETCOLOR="\[\e[00m\]"

  local git_branch='`git branch 2> /dev/null | grep ^* | sed -e "s/* \(.*\)/(\1) /"`'
  
  # export PS1="$GREEN\\w $CYAN$git_branch$RESETCOLOR\\$ "
}

# prompt
PROMPT_COMMAND='__git_ps1 "\[\033[0;32m\]\w\[\033[0;36m\]" "\[\e[00m\]\$ "'
# Save and reload the history after each command finishes
PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"
GIT_PS1_SHOWDIRTYSTATE="true"
GIT_PS1_DESCRIBE_STYLE="branch"
GIT_PS1_SHOWCOLORHINTS=""

source ~/termux-dotfiles/git-completion.bash

