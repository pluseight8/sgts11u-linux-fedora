# Установка

## Что требуется

* Samsung Galaxy Tab S11 Ultra со штатным Android; фактическая модель будет
  проверена через `getprop`;
* ARM64 (`uname -m` должен вернуть `aarch64`);
* Termux Android 7+ и все add-ons из одного источника подписи;
* Termux:X11 APK **и** `termux-x11-nightly` package;
* Termux:API для Android bridge; Termux:Boot — только для optional boot hook;
* свободное место: по умолчанию не менее 12 GiB;
* сеть и заряд батареи во время первоначальной загрузки Fedora/GNOME.

Не нужны bootloader unlock, Magisk, root, custom recovery, custom kernel,
Odin, Heimdall или отключение SELinux.

## Согласование источника Termux

Termux, Termux:X11, Termux:API, Termux:Boot и Termux:Widget должны быть из
одного signing source. GitHub и F-Droid APK нельзя смешивать. Установите
совместимый APK вручную из официального релиза Termux:X11, запустите его один
раз и разрешите notifications при необходимости.

## Ручные шаги

Самый простой bootstrap можно вставить одной строкой. Он не запускает
интерактивный `termux-setup-storage` и поэтому не смешивает его вопрос с
последующими командами:

```bash
pkg update -y && pkg upgrade -y && pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/pluseight8/sgts11u-linux-fedora/main/scripts/bootstrap.sh -o "$PREFIX/tmp/fedora-shell-bootstrap.sh" && bash "$PREFIX/tmp/fedora-shell-bootstrap.sh"
```

Или вручную:

```bash
pkg update -y
pkg upgrade -y
pkg install -y git
git clone https://github.com/pluseight8/sgts11u-linux-fedora.git "$HOME/fedora-galaxy"
cd "$HOME/fedora-galaxy"
./scripts/install.sh
```

`pkg upgrade -y` здесь обязателен: Termux использует rolling-release и не
поддерживает partial upgrades. `termux-setup-storage` запускайте отдельно, только если нужен доступ к общему
Android storage, и отвечайте `y` именно на его вопрос. `pkg install` в этой
инструкции использует `-y`, поэтому последующая вставка команд не может быть
принята за ответ `Y/n`.

Если `pkg` сообщает, что mirror не выбран, но затем успешно выбирает mirror и
читает package lists, это штатное автоматическое первоначальное определение.
При настоящей ошибке зеркала выполните `termux-change-repo` и повторите
bootstrap.

Installer:

1. собирает фактический device/Termux report;
2. отказывается работать в root shell и на не-ARM64 host;
3. проверяет модель (`SM-X930`/`SM-X936`), либо требует
   `--allow-unknown-device` для исследовательского запуска;
4. ставит `proot-distro`, `x11-repo`, `termux-x11-nightly` и bridge CLI;
5. скачивает `fedora:44` с `--architecture aarch64` через OCI registry;
6. запускает Fedora package setup;
7. копирует только проектные конфиги в container;
8. создаёт Termux:Widget shortcut `Fedora`;
9. выполняет quick diagnostics.

Повторный запуск безопасен: существующий container не удаляется и его данные
сохраняются, поэтому остановившуюся установку можно просто продолжить:

```bash
cd "$HOME/fedora-galaxy"
git pull --ff-only
./scripts/install.sh --yes
```

Для полного пересоздания используйте `./scripts/reset.sh` только после backup.

## Флаги installer

```text
--yes                    не задавать подтверждения
--allow-unknown-device   продолжить, если ro.product.model неизвестен
--enable-boot            установить ~/.termux/boot/fedora-shell
--skip-x11-package       не ставить termux-x11-nightly package
--experimental-gpu       установить optional virglrenderer-android, но не включать его в auto
--memory-profile NAME    auto, low, balanced или performance
--min-free-gib N         изменить минимальное свободное место
```

При повторном запуске bootstrap чистый checkout автоматически обновляется
через `git pull --ff-only`; локальные изменения он не трогает. Bootstrap
поддерживает `--dir DIRECTORY`, `--ref REF`, `--no-install` и
передаёт installer-флаги `--yes`, `--allow-unknown-device`, `--enable-boot`,
`--skip-x11-package`, `--experimental-gpu`, `--min-free-gib N`.

Флаг `--enable-boot` не превращает Android в Linux init. Termux:Boot запускает
скрипт best-effort после boot, но Android background restrictions и Samsung
battery policy могут потребовать ручной настройки. Основной безопасный путь —
запуск через shortcut после unlock.

## Запуск

```bash
./scripts/start.sh
```

По умолчанию:

* display — `:0`;
* Termux:X11 запускается отдельно;
* на Android 12+ автоматический запуск APK по умолчанию не выполняется из-за
  ограничений background activity; откройте Termux:X11 вручную. Для старого
  устройства/явного эксперимента можно задать `FEDORA_TERMUX_X11_AUTO_OPEN=on`;
* для SM-X930 включён совместимый `-legacy-drawing`, чтобы избежать чёрной
  поверхности; отключение для A/B-проверки: `TERMUX_X11_LEGACY_DRAWING=0`;
* `--shared-tmp` и `--shared-x11` передаются PRoot;
* `/storage/emulated/0` bind-ится как `/home/fedora/Android`, если доступен;
* GPU mode `auto` всегда выбирает стабильный Mesa `llvmpipe` software fallback;
  установленный experimental VirGL не включается неожиданно;
* для GNOME 49+ пробуется `gnome-shell --wayland --devkit`, для старых
  GNOME остаётся совместимый `gnome-shell --nested --wayland`;
* desktop portals в режиме `auto` запускаются только при доступном `/dev/fuse`;
  это предотвращает ошибку `xdg-document-portal` в обычном Android/PRoot;
* pure X11 не включается автоматически.

Пример явного выбора:

```bash
FEDORA_DISPLAY=:1 FEDORA_GPU_MODE=virpipe ./scripts/start.sh

# install.sh --experimental-gpu устанавливает bridge, но проверять его нужно явно:
FEDORA_GPU_MODE=virpipe FEDORA_PORTAL_MODE=off ./scripts/start.sh

# если нужен desktop portal и /dev/fuse реально доступен:
FEDORA_PORTAL_MODE=on ./scripts/start.sh
```

Полезные переменные (`FEDORA_GPU_MODE`, `FEDORA_PORTAL_MODE` и остальные)
описаны в `scripts/lib/common.sh` и в
`fedora/rootfs/image.env`.

### Профиль памяти для 12 GiB

`FEDORA_MEMORY_PROFILE=auto` измеряет `MemTotal` и на планшете с 12 GiB
выбирает `low`. Этот режим не удаляет GNOME и не трогает Android: он не
запускает автоматически `gnome-settings-daemon`, terminal, PipeWire и
индексатор Tracker, ограничивает glibc arena growth и выбирает виртуальный
режим nested monitor 2560×1600. Разрешение Android-панели от этого не меняется.
Нужную функцию можно включить точечно:

```bash
FEDORA_AUDIO_MODE=on FEDORA_SETTINGS_DAEMON=on \
  FEDORA_LAUNCH_TERMINAL=on ./scripts/start.sh
```

Для полного desktop-профиля используйте `FEDORA_MEMORY_PROFILE=balanced`.
Если Tracker уже был отключён предыдущим low-профилем, включите его явно:
`FEDORA_SEARCH_MODE=on`.
Для A/B-проверки native virtual mode используйте:
`FEDORA_NESTED_MODE_SPECS=2960x1848 FEDORA_MEMORY_PROFILE=low`.
Swap/zram проект не создаёт: этим безопасно управляет Android, а создание
Linux swap-файла в PRoot не даёт настоящего kernel swap.

Для one-tap запуска установите Termux:Widget из того же signing source и
используйте созданный shortcut `Fedora`. Android APK из `android/` — отдельный
опциональный launcher/emergency UI; сначала соберите и установите его вручную,
затем выдайте ему дополнительное разрешение Termux RUN_COMMAND.

## Termux:X11 fullscreen и touch

Откройте настройки Termux:X11 и включите fullscreen/touch mode. В зависимости
от прошивки Samsung может потребоваться отключить battery optimization для
Termux и Termux:X11. Проект не меняет SystemUI и не удаляет navigation/status
bars без пользовательского решения.

Базовые жесты Termux:X11 включают tap/double-tap, long tap, two-finger
right-click и scrolling. Это transport emulation, не полноценный Wayland
tablet backend.

## Первый тест

```bash
./scripts/diagnostics.sh --quick
./gpu/scripts/probe-gpu.sh
./scripts/diagnostics.sh --frame-pacing
```

Внутри Fedora отдельно:

```bash
./scripts/diagnostics.sh --fedora
```

`WORKING` можно присвоить компоненту только после сохранения вывода теста на
этом планшете.

## Обновление и удаление

Обычное обновление останавливает сессию, создаёт backup, подтягивает чистый
`main` checkout, обновляет Termux и Fedora packages, затем синхронизирует
установленное дерево и GNOME integration:

```bash
./scripts/update.sh
```

Если обновлять Termux packages не требуется:

```bash
./scripts/update.sh --no-termux

# оставить установленный код неизменным, обновляя только пакеты:
./scripts/update.sh --no-project
```

Перед удалением можно посмотреть точный scope:

```bash
./scripts/remove.sh --dry-run
```

Удаление после подтверждения:

```bash
./scripts/remove.sh
```

Удаляются только контейнер Fedora, установленное дерево Fedora Shell, его
shortcut/boot hook и state/logs. Checkout, backups, Termux packages, Android и
One UI сохраняются.

## Возврат к One UI

В Android Settings выберите Default apps → Home app → One UI Home. Android
launcher никогда не удаляется этим проектом. Если GNOME завис, из Termux
выполните:

```bash
./scripts/stop.sh
```

или откройте Android Settings через [Fedora Shell app](android/).
