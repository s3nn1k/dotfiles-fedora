# dotfiles-fedora

Персональные настройки поверх Fedora Sway Spin 44. Sway, foot и GTK; штатное окружение
Fedora сохраняется.

Telegram: первая установка - официальный latest tar.xz; обновления выполняет приложение.
Запуск: `telegram`.

## Установка

До запуска скрипта: установленная Fedora Sway, вход в сессию Sway, работающая сеть. Из
терминала внутри Sway (foot, Mod+Enter):

```bash
sudo dnf install -y git
git clone https://github.com/s3nn1k/dotfiles-fedora.git ~/dotfiles-fedora
~/dotfiles-fedora/scripts/bootstrap.sh
```

Скрипт идемпотентен и спросит sudo-пароль. Он ставит пакеты dnf, раскладывает
конфиги-симлинки, поднимает VPN mihomo (https-подписка обязательна), ставит официальный
Telegram, настраивает gh, клонирует личные репозитории с повторными попытками.

Существующие репозитории обновляются через `git pull --ff-only`: локальные правки,
задетые upstream, пропускают обновление с предупреждением, расхождение с origin
останавливает скрипт.

После ручной работы с ключом в nkp:

```bash
~/dotfiles-fedora/scripts/setup-secrets.sh unlock
```

## Структура

- `bin/` - команды, которые bootstrap ставит в `~/.local/bin` для других репозиториев:
  credentials-setup (линки и права `~/credentials`), git-crypt-repo (unlock/lock
  git-crypt-репозиториев), git-cred-read (git credential helper).
- `scripts/` - установка машины: bootstrap.sh, setup-secrets.sh (unlock/link секретов),
  mihomo-apply.sh (конфиг и служба mihomo).
- Раскладка и клавиши - репо keyd-cfqv8 (https://github.com/s3nn1k/keyd-cfqv8); xremap
  здесь не настраивается.
