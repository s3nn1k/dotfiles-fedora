# dotfiles-fedora

Персональные настройки поверх Fedora Sway Spin 44. Sway, foot и GTK; штатное окружение
Fedora сохраняется.

## Установка

До запуска скрипта: установленная Fedora Sway, вход в сессию Sway, работающая сеть. Из
терминала внутри Sway (foot, Mod+Enter):

```bash
sudo dnf install -y git
git clone https://github.com/s3nn1k/dotfiles-fedora.git ~/dotfiles-fedora
~/dotfiles-fedora/scripts/bootstrap.sh
~/dotfiles-fedora/scripts/cleanup.sh
```

После ручной работы с ключом в nkp:

```bash
~/dotfiles-fedora/scripts/setup-secrets.sh unlock
```

## Структура

- `bin/` - команды в `~/.local/bin` от bootstrap: credentials-setup (линки и права
  `~/credentials`), git-crypt-repo (unlock/lock git-crypt-репозиториев), git-cred-read
  (git credential helper), herdr-ws и herdr-agent-rename (панели и агенты herdr),
  swayidle-laptop (idle-контур Sway), wt (транскрибация ffmpeg + whisper.cpp).
- `herdr/config.toml` - конфиг herdr; bootstrap линкует в `~/.config/herdr/config.toml`.
- `psqlrc` - UX-конфиг psql; линкуется в `~/.psqlrc`.
- `sway/`, `foot/`, `swaylock/`, `gtk-3.0/`, `gtk-4.0/`, `zshrc`, `zprofile`, `gitconfig`,
  `wallpapers/` - конфиги, которые bootstrap раскладывает симлинками.
- `systemd/` - user-юнит ssh-agent и drop-in'ы logind и sleep (последние ставятся копиями
  в /etc).
- `mihomo/` - шаблон конфига VPN; `firefox/` - prefs, userChrome и политики Firefox.
- `scripts/bootstrap.sh` - установка машины с нуля: пакеты, конфиги, hardening, VPN
  mihomo, Telegram, gh, личные репозитории.
- `scripts/cleanup.sh` - срез балласта Fedora Sway Spin и миграция на Node.js 24
  (`--dry-run`).
- `scripts/hardening.sh` - sysctl, LLMNR off, avahi mask, firewall, PAM, auditd,
  автообновления безопасности.
- `scripts/mihomo-apply.sh` - рендер конфига mihomo из подписки и systemd-служба.
- `scripts/setup-secrets.sh` - unlock и линк git-crypt-секретов (postgres, firefox).
- `scripts/telegram-extract.py` - распаковка бинарника Telegram из официального tar.xz;
  запуск установленного приложения: `telegram`.
- `scripts/firefox/profiles.sh` - перенос закладок Firefox между машинами.
- Раскладка и клавиши - репо keyd-cfqv8 (https://github.com/s3nn1k/keyd-cfqv8); xremap
  здесь не настраивается.
