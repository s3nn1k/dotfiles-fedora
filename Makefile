.PHONY: lint test
lint:
	for script in scripts/*.sh bin/*.sh; do bash -n "$$script" || exit 1; done
	zsh -n zshrc
	zsh -n zprofile
test:
	tests/bootstrap.sh
