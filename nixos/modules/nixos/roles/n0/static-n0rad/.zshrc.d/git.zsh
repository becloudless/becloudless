
alias master="git checkout master"
# alias gitup='git add --all $(git rev-parse --show-toplevel); git commit -a -m up; git push'
alias gitaup='git add --all $(git rev-parse --show-toplevel); git commit --amend --no-edit; git push --force'
alias gp="git pull"
alias gptf="git pull --tags --force"
alias grebase="git fetch && git rebase origin/master"
alias gco="git checkout "
alias gco-="git checkout -"
gcd() {
  cd $(git rev-parse --show-toplevel)
}

function ggs {
  p="."
  if [ -z $* ]; then
    p=$1
  fi
  find $p -type d -not \( -name .terraform -prune \) -name .git -prune -print0 | while IFS= read -r -d '' file; do (cd $file/.. && [ ! -z "$(git status --porcelain)" ] && dirname $file); done
}

function gitup {
  git add --all $(git rev-parse --show-toplevel)
  echo -e "\e[0;93mCommit message: \e[0m"
  message=""
  vared message
  git commit -a -m "$message"; git push
}
function gcb {
  name="${*// /-}"
  if [[ ${name} != n0/* ]]; then
    name="n0/${name}"
  fi
  git checkout -b "${name}"
}
function gcom {
  git commit -m "$*"
}
function ghpr {
    local repo=`git remote -v | grep -m 1 "(push)" | sed -e "s/.*github.com[:/]\(.*\)\.git.*/\1/"`
    local branch=`git name-rev --name-only HEAD`
    echo "... creating pull request for branch \"$branch\" in \"$repo\""
    xdg-open "https://github.com/$repo/pull/new/$branch?expand=1"
}
function glb { # list branches
  git for-each-ref --sort=-committerdate refs/heads/ --format='%(committerdate:short) %(authorname) %(refname:short)' | head -n 10
}
function gsquash {
  if [ -n "$1" ]; then
    git reset --soft HEAD~$1 && git commit --edit -m"$(git log --format=%B --reverse HEAD..HEAD@{1})"
  fi
}
function gre {
  git fetch origin master
  git stash
  git rebase origin/master
  git stash pop
}
function grepush {
  git fetch origin master
  git stash
  git rebase origin/master
  git push --force
  git stash pop
}