HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=10000
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt SHARE_HISTORY
setopt APPEND_HISTORY

ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
[ ! -d "$ZINIT_HOME" ] && mkdir -p "$(dirname "$ZINIT_HOME")" && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "$ZINIT_HOME/zinit.zsh"

zinit ice wait lucid
zinit light zsh-users/zsh-autosuggestions

zinit ice wait lucid atload'_zsh_autosuggest_start'
zinit light zsh-users/zsh-syntax-highlighting

export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate zsh)"
eval "$(starship init zsh)"
eval "$(fzf --zsh)"

autoload -Uz compinit
compinit

[ -f "$HOME/dotfiles/.bash_aliases" ] && source "$HOME/dotfiles/.bash_aliases"

cd() {
  if [ $# -eq 0 ]; then
    builtin cd ~/dev
  else
    builtin cd "$@"
  fi
}

if [[ $SHLVL -eq 1 ]]; then
  cd ~/dev
fi

precmd () { echo -n "\x1b]1337;CurrentDir=$(pwd)\x07" }

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

#compdef just
source <(JUST_COMPLETE=zsh just)
if [ "$funcstack[1]" = "_just" ]; then
  _clap_dynamic_completer_just "$@"
fi
