.PHONY: lint
lint:
	for script in scripts/*.sh herdr/bin/*.sh waybar/*.sh bootstrap/lib.sh bootstrap/steps/*.sh; do bash -n "$$script" || exit 1; done
	shellcheck $$(find scripts bootstrap herdr -name '*.sh')
	find scripts swayidle -name '*.py' -print0 | PYTHONPYCACHEPREFIX=/tmp/dotfiles-pycache xargs -0 -r python3 -m py_compile
	jq empty waybar/config.jsonc
	jq -e '.policies | type == "object"' librewolf/policies.json >/dev/null
	zsh -n zshrc
	zsh -n zprofile
