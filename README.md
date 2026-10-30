# dotfiles-fedora

Персональные настройки поверх Fedora Sway Spin 44.
Sway, foot и GTK; штатное окружение Fedora сохраняется.

## Установка

До запуска скрипта: установленная Fedora Sway, вход в сессию Sway, работающая сеть.
Из терминала внутри Sway (foot, Mod+Enter):

```bash
sudo dnf install -y git
git clone https://github.com/s3nn1k/dotfiles-fedora.git ~/dotfiles-fedora
~/dotfiles-fedora/scripts/bootstrap.sh
```

Скрипт идемпотентен, спросит sudo-пароль.
