alias ff='fastfetch'
alias l='ls -alF'
alias gs='git status'
alias drm='docker rm -f $(docker ps -aq) && docker volume rm -f $(docker volume ls -q)'
alias dup='docker compose up -d --wait --build'
alias dcrm='docker rm -f $(docker ps -aq)'
alias dirm='docker image rm -f $(docker image ls -q)'
alias dvrm='docker volume rm -f $(docker volume ls -q)'
alias dpsa='docker ps -a --format="table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias dockerClean='docker system prune -af --volumes'
alias watchContainers="watch -n 1 'docker ps -a --format=\"table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\"'"
alias k='kubectl'
alias ncu='npx --yes npm-check-updates --format group --interactive -p pnpm'
alias dive='docker run -ti --rm  -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive'
alias dis='echo -n '\''Nom image Docker (tag optionnel) : '\'' && read image && echo '\''Taille approximative (Mo): '\''$(docker save $image | gzip -c | wc -c | awk '\''{printf "%.2f", $1/1048576}'\'') Mo'
alias ggh='cd $(git rev-parse --show-toplevel)'
UPDATE_STEP_STYLE='\e[1;30;43m'
UPDATE_DONE_STYLE='\e[1;30;42m'
UPDATE_RESET_STYLE='\e[0m'

function print_update_banner {
  printf "\n${1} %s ${UPDATE_RESET_STYLE}\n\n" "$2"
}

function update {
  print_update_banner "$UPDATE_STEP_STYLE" "1/3 System packages (apt)"
  sudo apt update -y && sudo apt full-upgrade -y && sudo apt autoremove --purge -y || return
  print_update_banner "$UPDATE_STEP_STYLE" "2/3 Tools (mise)"
  mise upgrade || return
  print_update_banner "$UPDATE_STEP_STYLE" "3/3 Claude Code instances (tmux)"
  if command -v claude >/dev/null && tmux list-sessions >/dev/null 2>&1; then
    ~/dotfiles/tmux/restart-claude.sh || return
  else
    echo "No Claude Code in tmux, nothing to reload"
  fi
  print_update_banner "$UPDATE_DONE_STYLE" "Update done"
}
