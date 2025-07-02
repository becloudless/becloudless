
zmodload zsh/datetime
function preexec() {
  __TIMER=$EPOCHREALTIME
}
function powerline_precmd() {
  local __ERRCODE=$?
  local __DURATION=0

  if [ -n $__TIMER ]; then
    local __ERT=$EPOCHREALTIME
    __DURATION="$(($__ERT - ${__TIMER:-__ERT}))"
  fi

  # eval "$(/usr/bin/powerline-go -duration $__DURATION -error $__ERRCODE -shell zsh -modules exit -eval -cwd-mode dironly -duration-min 2)"
  eval "$(powerline-go -duration $__DURATION -error $__ERRCODE -shell zsh -modules-right git,hg -modules venv,ssh,kube,cwd,perms,jobs,exit,duration -eval -cwd-mode dironly -duration-min 2)"
  unset __TIMER
}
function install_powerline_precmd() {
  for s in "${precmd_functions[@]}"; do
    if [ "$s" = "powerline_precmd" ]; then
      return
    fi
  done
  precmd_functions+=(powerline_precmd)
}
if [ "$TERM" != "linux" ]; then
    install_powerline_precmd
fi
