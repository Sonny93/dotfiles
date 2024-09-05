alias l='ls -alF'
alias gs='git status'
alias drm='docker rm -f $(docker ps -aq) && docker volume rm -f $(docker volume ls -q)'
alias dcrm='docker rm -f $(docker ps -aq)'
alias dirm='docker image rm -f $(docker image ls -q)'
alias dvrm='docker volume rm -f $(docker volume ls -q)'
alias dpsa='docker ps -a --format="table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias watchContainers="watch -n 1 'docker ps -a --format=\"table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\"'"
alias wc="watch -n 1 'docker ps -a --format=\"table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\"'"
alias k='kubectl'
alias ncu='npx npm-check-updates --format group --interactive -p pnpm'