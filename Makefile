ZSHRC_PATH := $(HOME)/.zshrc
CUSTOM_ZSHRC := $(HOME)/dotfiles/.zshrc

ZSHENV_PATH := $(HOME)/.zshenv
CUSTOM_ZSHENV := $(HOME)/dotfiles/.zshenv

GITCONFIG_PATH := $(HOME)/.gitconfig
CUSTOM_GITCONFIG := $(HOME)/dotfiles/.gitconfig

.PHONY: apply
apply:
	@# Ajout conditionnel pour .zshrc
	@{ if ! grep -q "source \$$HOME/dotfiles/.zshrc" $(ZSHRC_PATH); then \
		echo "\n# Import custom .zshrc (conditionally loaded)" >> $(ZSHRC_PATH); \
		echo "[ -f \$$HOME/dotfiles/.zshrc ] && source \$$HOME/dotfiles/.zshrc" >> $(ZSHRC_PATH); \
		echo "Conditional custom .zshrc import added to $(ZSHRC_PATH)."; \
	else \
		echo "Conditional custom .zshrc import already present in $(ZSHRC_PATH)."; \
	fi; }

	@# Ajout conditionnel pour .zshenv
	@{ if ! grep -q "source \$$HOME/dotfiles/.zshenv" $(ZSHENV_PATH); then \
		echo "\n# Import custom .zshenv (conditionally loaded)" >> $(ZSHENV_PATH); \
		echo "[ -f \$$HOME/dotfiles/.zshenv ] && source \$$HOME/dotfiles/.zshenv" >> $(ZSHENV_PATH); \
		echo "Conditional custom .zshenv import added to $(ZSHENV_PATH)."; \
	else \
		echo "Conditional custom .zshenv import already present in $(ZSHENV_PATH)."; \
	fi; }

	@# Vérifie et crée .gitconfig si nécessaire
	@{ if [ ! -f "$(GITCONFIG_PATH)" ]; then \
		echo "$(GITCONFIG_PATH) not found. Creating an empty Git configuration file..."; \
		echo "# Main Git configuration" > $(GITCONFIG_PATH); \
		echo "$(GITCONFIG_PATH) created."; \
	fi; }

	@# Ajoute l'include conditionnel pour .gitconfig
	@{ if ! grep -q "path = $(CUSTOM_GITCONFIG)" $(GITCONFIG_PATH); then \
		echo "" >> $(GITCONFIG_PATH); \
		echo "# Include custom .gitconfig" >> $(GITCONFIG_PATH); \
		echo "[include]" >> $(GITCONFIG_PATH); \
		echo "    path = $(CUSTOM_GITCONFIG)" >> $(GITCONFIG_PATH); \
		echo "Custom .gitconfig include added to $(GITCONFIG_PATH)."; \
	else \
		echo "Custom .gitconfig include already present in $(GITCONFIG_PATH)."; \
	fi; }
