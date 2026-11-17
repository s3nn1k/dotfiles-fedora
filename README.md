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
```

Точечный шаг: `~/dotfiles-fedora/scripts/bootstrap.sh <шаг>`; список шагов - `--list`.
Секреты: `~/dotfiles-fedora/scripts/unlock-gitcrypt.sh` - ключ credentials, после него

## Структура

- `bootstrap/` - `lib.sh` (хелперы: симлинки, загрузки по checksum, клоны, git-crypt) и
  `steps/` (19 шагов); порядок задаёт STEP_ORDER в диспетчере `scripts/bootstrap.sh`.
- `scripts/unlock-gitcrypt.sh` - разблокировка git-crypt в `~/credentials`
  (машинерия - `~/credentials/scripts/git-crypt-repo.sh`), canary-проверка, раскладка
  credentials, шаг mihomo.
- `librewolf/` - настройки браузера: `user.js`, тема (`chrome/`), `policies.json`; шаг
  `librewolf` линкует их в существующие профили, профили создаются в панели браузера.
- `herdr/` - конфиг herdr и `bin/` панели (herdr-ws, herdr-agent-rename).
- `sway/` - конфиги Sway; `swayidle/` - `swayidle-laptop.py`; `foot/`, `swaylock/`, `rofi/`, `waybar/`,
  `dunst/`, `gtk-3.0/`, `gtk-4.0/`, `fontconfig/` - остальной рабочий стол, всё
  раскладывается симлинками.
- `sddm/` - тема greeter; `omp/` - промпт oh-my-posh; `wallpapers/` - обои.
- `mihomo/` - шаблон конфига VPN.
- `mpd/mpd.conf`, `rmpc/config.ron`, `herdr/config.toml`, `psqlrc`, `zshrc`, `zprofile`,
  `gitconfig` - конфиги, линкуются в дом; медиа-клавиши (mpc, wpctl) в
  `sway/desktop.conf`.
- `systemd/` - user-юниты ssh-agent и mpd-mpris (мост MPRIS для медиа-клавиш) и drop-in'ы
  logind и sleep (последние ставятся копиями в /etc).
- Раскладка и клавиши - репо keyd-cfqv8 (https://github.com/s3nn1k/keyd-cfqv8); xremap
  здесь не настраивается.
