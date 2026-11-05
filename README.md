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
конфиги-симлинки, применяет security-hardening (sysctl, LLMNR off, avahi mask, срез
ssh/mdns из firewall, автообновления безопасности), поднимает VPN mihomo
(https-подписка обязательна), ставит официальный Telegram, настраивает gh, клонирует
личные репозитории с повторными попытками.

Существующие репозитории обновляются через `git pull --ff-only`: локальные правки, задетые
upstream, пропускают обновление с предупреждением, расхождение с origin останавливает
скрипт.

Питание: после 300 секунд бездействия экран блокируется, через 600 секунд выключается, а
сон наступает через 300 секунд на батарее или 1800 секунд от сети. Bootstrap ставит
переопределения Sway и systemd; новый контур idle стартует при входе в сессию Sway (reload
его не перезапускает), настройки крышки logind применит после следующей перезагрузки.
Блокировка и выключение экранов позволяют pi работать, сон приостанавливает его.

После bootstrap запусти `~/dotfiles-fedora/scripts/cleanup.sh`: срезает балласт Fedora
Sway Spin (чужие firmware, гостевые агенты гипервизоров, остатки установщика, печать,
телеметрия) и мигрирует на Node.js 24; `--dry-run` показывает план без изменений.

После ручной работы с ключом в nkp:

```bash
~/dotfiles-fedora/scripts/setup-secrets.sh unlock
```

## Структура

- `bin/` - команды, которые bootstrap ставит в `~/.local/bin`: credentials-setup (линки и
  права `~/credentials`), git-crypt-repo (unlock/lock git-crypt-репозиториев),
  git-cred-read (git credential helper), herdr-ws (фокус и переносы панелей herdr по
  позиции сайдбара 1..10), swayidle-laptop (idle-контур: блокировка, выключение экрана,
  сон), wt (транскрибация: ffmpeg + whisper.cpp).
- `herdr.toml` - конфиг herdr (терминальный менеджер панелей и воркспейсов); bootstrap
  линкует его в `~/.config/herdr/config.toml`.
- `psqlrc` - UX-конфиг psql (pager off, `\x auto`, timing, промпт `user@host:port` и
  текущая база); bootstrap линкует его в `~/.psqlrc`, `credentials-setup` линкует
  postgres-креды из `~/credentials` в `~/.pgpass` и `~/.pg_service.conf`.
- `scripts/` - установка машины: bootstrap.sh, setup-secrets.sh (unlock/link секретов),
  mihomo-apply.sh (конфиг и служба mihomo), hardening.sh (sysctl, LLMNR off, avahi mask,
  срез ssh/mdns из firewall, автообновления безопасности, PAM, sudo-логи, gpgcheck,
  banners).
- `scripts/firefox-profiles.sh` - перенос закладок Firefox (без истории) и cookies между
  машинами: init/push/pull/reset через `~/credentials/firefox`; профили появляются в
  панели Firefox.
- Раскладка и клавиши - репо keyd-cfqv8 (https://github.com/s3nn1k/keyd-cfqv8); xremap
  здесь не настраивается.
