.PHONY: lint
lint:
	for script in scripts/*.sh scripts/librewolf/*.sh bin/*.sh; do bash -n "$$script" || exit 1; done
	find scripts bin -name '*.py' -print0 | PYTHONPYCACHEPREFIX=/tmp/dotfiles-pycache xargs -0 -r python3 -m py_compile
	jq empty waybar/config.jsonc
	zsh -n zshrc
	zsh -n zprofile
