alias l='ls -alF'
alias gs='git status'
alias ctForceRemove='docker rm -f $(docker ps -aq)'
alias imgForceRemove='docker image rm -f $(docker image ls -q)'
alias vlForceRemove='docker volume rm -f $(docker volume ls -q)'
alias dpsa='docker ps -a --format="table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias watchContainers="watch -n 1 'docker ps -a --format=\"table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\"'"
