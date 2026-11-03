.PHONY: lint
lint:
	for script in scripts/*.sh bin/*.sh; do bash -n "$$script" || exit 1; done
	PYTHONPYCACHEPREFIX=/tmp/dotfiles-pycache python3 -m py_compile scripts/*.py || exit 1
	zsh -n zshrc
	zsh -n zprofile
