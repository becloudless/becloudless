
########################
## MAN
########################
function colored() {
	command env \
		LESS_TERMCAP_mb=$(printf "\e[1;31m") \
		LESS_TERMCAP_md=$(printf "\e[1;31m") \
		LESS_TERMCAP_me=$(printf "\e[0m") \
		LESS_TERMCAP_se=$(printf "\e[0m") \
		LESS_TERMCAP_so=$(printf "\e[1;44;33m") \
		LESS_TERMCAP_ue=$(printf "\e[0m") \
		LESS_TERMCAP_us=$(printf "\e[1;32m") \
		PAGER="${commands[less]:-$PAGER}" \
		_NROFF_U=1 \
		PATH="$HOME/bin:$PATH" \
			"$@"
}

function format_plan () {
	awk '
    /Terraform will perform the following actions:/ { found=1 }
    /------------------------------------------------------------------------/ { found=0 }
    // { if (found) { print $0 } }
  ' | (
		printf '<details><summary>Plan for %s</summary>\n\n```diff\n\n' "$1" && perl -pe 's/\x1b\[[0-9;]*[mG]//g' | sed -e 's/^\(  *\)\([\+-]\)/\2\1/' -e 's/^\(  *\)~/!\1/' && printf '```\n</details>'
	) | pbcopy
}

function man {
	colored $0 "$@"
}

########################
## directories
########################
# Changing/making/removing directory
setopt auto_pushd
setopt pushd_ignore_dups
setopt pushdminus

function d () {
  if [[ -n $1 ]]; then
    dirs "$@"
  else
    dirs -v | head -10
  fi
}
compdef _dirs d

########################
## BASE
########################
export PATH=$HOME/.local/bin:$HOME/.bin:$PATH
export EDITOR="/home/n0rad/.local/bin/code-editor.sh"
export BROWSER="chromium-browser"
export LESS='-R --quit-if-one-screen --no-init '
export LESSOPEN='|colorize-file %s'
export PAGER='less'
export WORDCHARS='*?.[]~=&;!#$%^(){}<>'

########################
## Aliases
########################
alias ls="ls --color"
alias l="ls -lh"
alias ll='ls -ll'
alias la="ls -lah"
alias cd..='cd ..'
alias sha1='openssl sha1'
# alias y="yt-dlp -o '~/Videos/TMP/%(uploader)s/%(title)s-%(id)s.%(ext)s' $*"
alias v='vim $*'
alias grpe=grep
alias h='history'
alias sshi='ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
alias scpi='scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
alias meminfo='free -m -l -t'
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias pscpu='ps auxf | sort -nr -k 3'
alias pscpu10='ps auxf | sort -nr -k 3 | head -10'
alias cpuinfo='lscpu'
alias ports='netstat -tulanp'

alias -g ...='../..'
alias -g ....='../../..'
alias -g .....='../../../..'
alias -g ......='../../../../..'
alias ..='cd ..'
alias ...='cd ../../../'
alias ....='cd ../../../../'
alias .....='cd ../../../../'


#echo_yellow() { echo -e -n "\e[0;93m$1\e[0m" ; echo "$2";}
#echo_red()    { echo -e -n "\e[0;31m$1\e[0m" ; echo "$2";}
#echo_purple() {	echo -e -n "\e[0;35m$1\e[0m" ; echo "$2";}
#echo_cyan()   { echo -e -n "\e[0;36m$1\e[0m" ; echo "$2";}
