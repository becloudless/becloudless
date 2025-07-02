HISTFILE="/nix/users/home/n0rad/.zsh_history"
HISTSIZE=10000000
SAVEHIST=10000000
export HISTCONTROL=ignoreboth

## History command configuration
setopt extended_history       # record timestamp of command in HISTFILE
setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_dups       # ignore duplicated commands history list
setopt hist_ignore_space      # ignore commands that start with space
setopt hist_verify            # show command with history expansion to user before running it
setopt share_history          # share command history data
setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt inc_append_history


setopt interactivecomments # recognize comments
setopt long_list_jobs

export ZSH_CACHE_DIR=~/.cache/zsh

########################
## KEYS
########################
#source /usr/share/oh-my-zsh/lib/key-bindings.zsh

bindkey '\ew' kill-region                             # [Esc-w] - Kill from the cursor to the mark
bindkey -s '\el' 'ls\n'                               # [Esc-l] - run command: ls
bindkey '^r' history-incremental-search-backward      # [Ctrl-r] - Search backward incrementally for a specified string. The string may begin with ^ to anchor the search to the beginning of the line.
bindkey ' ' magic-space                               # [Space] - don't do history expansion
bindkey "^[[1;3C" forward-word
bindkey "^[[1;3D" backward-word
bindkey "\b" backward-kill-word


# ###############
# # async
# ###############
# {
#     # RUN
# } &!
