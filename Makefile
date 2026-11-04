.PHONY: lint test
lint:
	for script in scripts/*.sh bin/*.sh; do bash -n "$$script" || exit 1; done
	zsh -n zshrc
	zsh -n zprofile

test:
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
