# On ne recréer pas le fichier .zshrc de base, on modifie juste les valeurs qui nous intéressent.

# Set the theme to amuse
ZSH_THEME="powerlevel10k/powerlevel10k"

# Load bash aliases
source $HOME/dotfiles/.bash_aliases

# Auto update oh-my-zsh
zstyle ':omz:update' mode auto

# Enable command auto-correction
plugins=(git docker docker-compose node npm zsh-autosuggestions)

# Initialize fzf if it exists
if [ -f ~/.fzf.zsh ]; then
  source ~/.fzf.zsh
fi