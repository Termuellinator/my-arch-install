# My Dotfiles

## Installation

To install, run `stow -t ~ */` from this directory

Create file `/etc/zsh/zshenv` with content:
```
export ZDOTDIR=$HOME/.config/zsh
export HISTFILE=$HOME/.config/zsh/history
```
and install:
```
sudo pacman -S zsh-autosuggestions zsh-completions zsh-history-substring-search zsh-syntax-highlighting
