.PHONY: lint test
lint:
	for script in scripts/*.sh bin/*.sh tests/*.sh; do bash -n "$$script" || exit 1; done
	zsh -n zshrc
	zsh -n zprofile

test:
	./tests/herdr-ws.sh
