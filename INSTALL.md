# Установка

## Что требуется

* Samsung Galaxy Tab S11 Ultra со штатным Android; фактическая модель будет
  проверена через `getprop`;
* ARM64 (`uname -m` должен вернуть `aarch64`);
* Termux Android 7+ и все add-ons из одного источника подписи;
* Termux:X11 APK **и** `termux-x11-nightly` package;
* Termux:API для optional read-only Android probes; Termux:Boot — необязательный безопасный observer;
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
bash ./scripts/install.sh
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

`bash ./scripts/install.sh` в ручной инструкции намеренно переживает старый
checkout, в котором Git потерял executable bits. После первого успешного
запуска installer сам восстановит права всех проектных launcher-файлов.

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
bash ./scripts/install.sh --yes
```

Для полного пересоздания используйте `bash ./scripts/reset.sh` только после backup.

## Флаги installer

```text
--yes                    не задавать подтверждения
--allow-unknown-device   продолжить, если ro.product.model неизвестен
--enable-boot            установить безопасный observer в ~/.termux/boot/fedora-shell
--skip-x11-package       не ставить termux-x11-nightly package
--experimental-gpu       установить optional virglrenderer-android, но не включать его в auto
--memory-profile NAME    auto, low, balanced или performance
--min-free-gib N         изменить минимальное свободное место
```

## Первоначальная GUI-настройка

Android APK из `android/` устанавливается вручную пользователем; installer не
скачивает его и не устанавливает никакие APK. После установки:

1. Откройте `Fedora Shell` как обычное приложение.
2. В мастере проверьте Termux и Termux:X11, откройте Termux:X11 и включите
   touch вручную. Для работающего свайпа снизу оставьте `Fullscreen on device
   display` выключенным; проект не изменяет эту настройку Android.
3. Выдайте Fedora Shell разрешение Termux `Run commands in Termux environment`
   и, если используется внешний контроллер, задайте в Termux
   `allow-external-apps=true`. Это явные действия пользователя.
4. Запустите read-only diagnostics и завершите мастер галочкой безопасности.
5. Необязательно нажмите `Попробовать выбрать Fedora Shell как Home`: Android
   сам покажет системный запрос `ROLE_HOME`. Если запрос отменён, откройте
   `Default apps → Home app` вручную. One UI Home остаётся установленным.

Мастер не меняет Android settings, AppOps, package/process state, SystemUI,
LMKD, zRAM, kernel или hardware services. Его проверки — только чтение; Fedora
Shell является лишь кандидатом Home до явного решения Android и пользователя.

## Android-приложения внутри рабочего сценария Fedora

После запуска Linux Mode Fedora автоматически запрашивает у локального
Termux-брокера список пользовательских Android-пакетов с launcher activity и
создаёт записи `Android: ...` в меню GNOME. При необходимости нажмите
`Refresh Android applications` либо выполните в терминале Fedora:

```bash
fedora-android-bridge list-apps
fedora-android-bridge sync-apps
```

Запись запускает выбранное приложение штатным Android resolver. Приложение
остаётся Android Activity и визуально появляется поверх Termux:X11; нативного
встраивания Android Activity в Wayland нет. Это ожидаемая граница rootless
архитектуры. Если Android 12+/One UI отклонит запуск из background, оставьте
Termux:X11 открытым и повторите действие. При недоступном resolver старый
каталог сохраняется.

Тот же refresh можно отправить кнопкой **Refresh Android apps in Fedora** в
Android-контроллере. Она работает только для уже запущенной видимой Fedora
сессии и не запускает скрытый PRoot-процесс.

Синхронизация не устанавливает, не отключает, не приостанавливает и не
завершает Android-процессы. Для отключения автоматического обновления каталога
добавьте в пользовательскую конфигурацию `FEDORA_ANDROID_APPS_MODE=off`;
`auto`/`on` включают его снова. Это настройка Fedora/Termux, не Android policy.

## Linux Mode без изменения Android

После завершения мастера включайте режим кнопкой `Linux Mode ON` в APK либо из
Termux:

```bash
bash "$HOME/.local/share/fedora-shell/scripts/linux-mode.sh" setup-status
bash "$HOME/.local/share/fedora-shell/scripts/linux-mode.sh" enable --profile linux-focused
```

`linux-focused` рекомендован для SM-X930 с 12 GiB: он экономит только Fedora
helpers, compositor buffers и необязательные Fedora-службы. Доступны также
`balanced` и `maximum-linux`; последний не управляет Android агрессивнее, а
только выбирает ещё более консервативные параметры Fedora. В частности,
`maximum-linux` использует nested monitor 1600×1000, `MALLOC_ARENA_MAX=1` и
более ранний allocator trim ценой масштаба/плавности. Остановка:

```bash
bash "$HOME/.local/share/fedora-shell/scripts/linux-mode.sh" disable
```

Команда `disable` останавливает только записанные процессы Fedora/Termux и не
пытается назначить Home программно. Для возврата к One UI выберите `One UI
Home` в системном экране `Home app` или нажмите одноимённую кнопку в Fedora
Shell. При сбое используйте:

```bash
bash "$HOME/.local/share/fedora-shell/scripts/linux-mode.sh" recover
```

Профили и состояние не являются Android memory governor: файл
`config/android-memory-allowlist.json` используется только для маркировки
read-only отчётов, а `integration/android-memory-governor.sh` измеряет общую
RAM/PSS/PSI/zRAM без применения политик к Android.

Это единственная допустимая «оптимизация Android» в проекте: наблюдение и
подсказки. Android сам решает, когда замораживать cached apps, reclaim-ить
память и использовать zRAM. Пользовательские battery/background настройки,
если они когда-либо понадобятся, меняются только вручную в Android UI и не
сохраняются этим проектом.

В `memory-latest.json` поле `recommendations` объясняет, что делать при
давлении: сначала уменьшать Fedora-side workload и виртуальные буферы, а не
вмешиваться в Android. Рекомендации advisory и не выполняют команды.

При повторном запуске bootstrap чистый checkout автоматически обновляется
через `git pull --ff-only`; локальные изменения он не трогает. Bootstrap
поддерживает `--dir DIRECTORY`, `--ref REF`, `--no-install` и
передаёт installer-флаги `--yes`, `--allow-unknown-device`, `--enable-boot`,
`--skip-x11-package`, `--experimental-gpu`, `--min-free-gib N`.

Флаг `--enable-boot` не превращает Android в Linux init и не запускает скрытый
Fedora/PRoot-процесс. Он устанавливает совместимый observer, который
намеренно ничего не запускает в фоне: выбранная пользователем Fedora Shell
Home Activity сама начинает Linux Mode после появления на экране. Это не
создаёт лишний расход RAM и не обходит Android background restrictions.
Основной путь — выбрать Fedora Shell как Home и использовать её видимый
переключатель.

## Запуск

```bash
bash ./scripts/start.sh
```

По умолчанию:

* display — `:0`;
* Termux:X11 запускается отдельно;
* на Android 12+ автоматический запуск APK по умолчанию не выполняется из-за
  ограничений background activity; откройте Termux:X11 вручную. Для старого
  устройства/явного эксперимента можно задать `FEDORA_TERMUX_X11_AUTO_OPEN=on`;
  если используется Android-контроллер из `android/`, его кнопка Start сначала
  открывает Termux:X11 в foreground и затем отправляет команду в Termux;
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

При запуске Linux Mode профиль `FEDORA_KEYBOARD_MODE=linux` оставляет обычные
клавиатурные события за сфокусированной Activity Termux:X11, а затем за
Wayland/Mutter/GNOME. Откройте Termux:X11, тапните по Fedora-поверхности и для
нижней навигации оставьте `Fullscreen on device display` выключенным.
Системные Home/Back, громкость, шторка, скриншоты и DeX остаются под контролем
Android SystemUI; приложение не может безопасно перехватить их через публичный
SDK. Проект не меняет Android keymap, IME, Accessibility или overlay. Read-only
проверка:

```bash
bash "$HOME/.local/share/fedora-shell/input/keyboard-mode.sh" status --read-preferences
```

Пример явного выбора:

```bash
FEDORA_DISPLAY=:1 FEDORA_GPU_MODE=virpipe bash ./scripts/start.sh

# install.sh --experimental-gpu устанавливает bridge, но проверять его нужно явно:
FEDORA_GPU_MODE=virpipe FEDORA_PORTAL_MODE=off bash ./scripts/start.sh

# если нужен desktop portal и /dev/fuse реально доступен:
FEDORA_PORTAL_MODE=on bash ./scripts/start.sh
```

Полезные переменные (`FEDORA_GPU_MODE`, `FEDORA_PORTAL_MODE` и остальные)
описаны в `scripts/lib/common.sh` и в
`fedora/rootfs/image.env`.

### Профиль памяти для 12 GiB

`FEDORA_MEMORY_PROFILE=auto` измеряет `MemTotal` и на планшете с 12 GiB
выбирает `low`. Этот режим не удаляет GNOME и не трогает Android: он не
запускает автоматически `gnome-settings-daemon`, terminal, WirePlumber,
pipewire-pulse, keyring, Evolution/GOA calendar helpers и индексатор Tracker,
но оставляет изолированный минимальный PipeWire display transport, обязательный
для Mutter Devkit. Он также ограничивает glibc arena growth, отключает
внутренний Xwayland и выбирает виртуальный nested monitor 1920×1200. Разрешение
Android-панели от этого не меняется. Нужную функцию можно включить точечно:

```bash
FEDORA_AUDIO_MODE=on FEDORA_SETTINGS_DAEMON=on \
  FEDORA_LAUNCH_TERMINAL=on bash ./scripts/start.sh
```

Для полного desktop-профиля используйте `FEDORA_MEMORY_PROFILE=balanced`.
Если Tracker уже был отключён предыдущим low-профилем, включите его явно:
`FEDORA_SEARCH_MODE=on`.
Для A/B-проверки native virtual mode используйте:
`FEDORA_NESTED_MODE_SPECS=2960x1848 FEDORA_MEMORY_PROFILE=low`.
Swap/zram проект не создаёт: этим безопасно управляет Android, а создание
Linux swap-файла в PRoot не даёт настоящего kernel swap.

### RAM Plus Samsung

RAM Plus нельзя включить из Fedora Shell без нарушения Android safety contract.
При желании включите его вручную в Android: `Настройки → Обслуживание устройства
→ Память → RAM Plus`; прошивка может попросить перезапуск. Эта функция использует
внутреннее хранилище как виртуальную память и не превращает планшет в устройство
с дополнительными 12 GiB физической RAM. Проект только показывает доступные
косвенные zRAM/swap-метрики в read-only отчёте и никогда не пишет Android
settings, LMKD, zRAM или kernel parameters.

На практике RAM Plus не является способом заставить Android занимать «почти
ноль» RAM: Android сам использует cached-app reclaim, zRAM и low-memory policy.
Безопасная оптимизация в этом проекте — закрывать тяжёлые Fedora-приложения,
держать low-профиль и уменьшать nested compositor buffers; системные Android
процессы и пользовательские приложения проект не удаляет и не force-stop-ит.

Для one-tap запуска установите Termux:Widget из того же signing source и
используйте созданный shortcut `Fedora`. Android APK из `android/` — отдельный
launcher/emergency UI с обязательным первоначальным GUI-мастером; сначала соберите и установите его вручную,
затем выдайте ему дополнительное разрешение Termux RUN_COMMAND.

## Termux:X11 fullscreen и touch

Откройте настройки Termux:X11 и включите touch mode. Для нижнего свайпа и
кнопок Android оставьте `Fullscreen on device display` выключенным: именно
отдельное Android-приложение Termux:X11 владеет видимой поверхностью и может
скрывать системную навигацию. Проект не меняет эту настройку автоматически,
не меняет SystemUI и не удаляет navigation/status bars. В зависимости от
прошивки Samsung может потребоваться вручную отключить battery optimization
для Termux и Termux:X11.

Базовые жесты Termux:X11 включают tap/double-tap, long tap, two-finger
right-click и scrolling. Это transport emulation, не полноценный Wayland
tablet backend.

## Первый тест

```bash
bash ./scripts/diagnostics.sh --quick
bash ./gpu/scripts/probe-gpu.sh
bash ./scripts/diagnostics.sh --frame-pacing
```

Внутри Fedora отдельно:

```bash
bash ./scripts/diagnostics.sh --fedora
```

`WORKING` можно присвоить компоненту только после сохранения вывода теста на
этом планшете.

## Обновление и удаление

Обычное обновление останавливает сессию, создаёт backup, подтягивает чистый
`main` checkout, обновляет Termux и Fedora packages, затем синхронизирует
установленное дерево и GNOME integration:

```bash
bash ./scripts/update.sh
```

Если обновлять Termux packages не требуется:

```bash
bash ./scripts/update.sh --no-termux

# оставить установленный код неизменным, обновляя только пакеты:
bash ./scripts/update.sh --no-project
```

Перед удалением можно посмотреть точный scope:

```bash
bash ./scripts/remove.sh --dry-run
```

Удаление после подтверждения:

```bash
bash ./scripts/remove.sh
```

Удаляются только контейнер Fedora, установленное дерево Fedora Shell, его
shortcut/boot hook и state/logs. Checkout, backups, Termux packages, Android и
One UI сохраняются.

## Возврат к One UI

В Android Settings выберите Default apps → Home app → One UI Home. Android
launcher никогда не удаляется этим проектом. Если GNOME завис, из Termux
выполните:

```bash
bash ./scripts/stop.sh
```

или откройте Android Settings через [Fedora Shell app](android/).
