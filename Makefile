ZSHRC_PATH := $(HOME)/.zshrc
CUSTOM_ZSHRC := $(HOME)/dotfiles/.zshrc

ZSHENV_PATH := $(HOME)/.zshenv
CUSTOM_ZSHENV := $(HOME)/dotfiles/.zshenv

.PHONY: apply
apply:
	@if ! grep -q "source \$$HOME/dotfiles/.zshrc" $(ZSHRC_PATH); then \
		echo "\n# Import custom .zshrc (conditionally loaded)" >> $(ZSHRC_PATH); \
		echo "[ -f \$$HOME/dotfiles/.zshrc ] && source \$$HOME/dotfiles/.zshrc" >> $(ZSHRC_PATH); \
		echo "Conditional custom .zshrc import added to $(ZSHRC_PATH)."; \
	else \
		echo "Conditional custom .zshrc import already present in $(ZSHRC_PATH)."; \
	fi

	@if ! grep -q "source \$$HOME/dotfiles/.zshenv" $(ZSHENV_PATH); then \
		echo "\n# Import custom .zshenv (conditionally loaded)" >> $(ZSHENV_PATH); \
		echo "[ -f \$$HOME/dotfiles/.zshenv ] && source \$$HOME/dotfiles/.zshenv" >> $(ZSHENV_PATH); \
		echo "Conditional custom .zshenv import added to $(ZSHENV_PATH)."; \
	else \
		echo "Conditional custom .zshenv import already present in $(ZSHENV_PATH)."; \
	fi
