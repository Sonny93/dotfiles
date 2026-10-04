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

zinit snippet OMZL::key-bindings.zsh

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
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|=*' 'l:|=* r:|=*'

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

TAB_TITLE_MAX_COMMAND_LENGTH=30

set_tab_title() {
  printf '\e]0;%s\a' "$1"
}

current_location() {
  local gitRootPath
  gitRootPath=$(git rev-parse --show-toplevel 2>/dev/null)

  if [[ -z "$gitRootPath" ]]; then
    print -P '%2~'
    return
  fi

  local repositoryName="${gitRootPath:t}"
  local relativePath="${PWD#"$gitRootPath"}"
  relativePath="${relativePath#/}"

  if [[ -z "$relativePath" ]]; then
    echo "$repositoryName"
  else
    echo "$repositoryName/$relativePath"
  fi
}

show_idle_title() {
  set_tab_title "$(current_location)"
}

show_running_title() {
  local collapsedCommand="${1//$'\n'/ }"

  if [[ ${#collapsedCommand} -gt $TAB_TITLE_MAX_COMMAND_LENGTH ]]; then
    collapsedCommand="${collapsedCommand[1,$TAB_TITLE_MAX_COMMAND_LENGTH]}…"
  fi

  set_tab_title "▶ $collapsedCommand · $(current_location)"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd show_idle_title
add-zsh-hook preexec show_running_title

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
