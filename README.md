# Fedora Shell для Galaxy Tab S11 Ultra

Безопасный research-first прототип Fedora ARM64 + GNOME поверх штатного Android
на Samsung Galaxy Tab S11 Ultra.

Проект намеренно не является прошивкой и не пытается заменить Android. Он
использует Android как низкоуровневую аппаратную платформу, Termux как среду
запуска, PRoot-Distro как rootless userspace и GNOME как основной desktop UI.

## Важное ограничение

Этот репозиторий не разблокирует bootloader, не требует root и не изменяет
boot/vendor_boot/init_boot/vbmeta/DTB/DTBO, kernel, recovery, разделы Android,
Knox, modem или EFS. Никакие команды из проекта не используют Odin или
Heimdall. Удаление контейнера и пользовательских файлов проекта не требует
factory reset и не должно влиять на OTA Android.

По журналам, предоставленным владельцем устройства, подтверждены Samsung
`SM-X930`, Android 16/API 36 и host `aarch64`. Это не заменяет полный probe:
SoC properties, Vulkan, фактический renderer, touch/S Pen, audio, refresh
pacing и suspend/resume всё равно нужно проверять на самом планшете; результаты
разделены в `STATUS.md` на наблюдённые и неподтверждённые.

## Два пользовательских режима

`Android Mode` — обычный One UI. `Linux Mode` — пользовательский foreground/Home
слой Fedora через Termux:X11 и PRoot. Android остаётся host OS: kernel, драйверы,
SurfaceFlinger, SystemUI, сеть, звук, Bluetooth, S Pen, батарея и сенсоры не
заменяются. Fedora Shell лишь может стать кандидатом `ROLE_HOME`; окончательный
выбор делает штатный Android экран Home app, а One UI Home не удаляется и не
отключается.

Первоначальный Android APK показывает GUI-мастер, проверяет наличие Termux и
Termux:X11 только чтением и просит явное подтверждение перед завершением setup.
Все остальные переключения относятся к Fedora/Termux user space. Проект не
изменяет Android settings, AppOps, package state, процессы, LMKD, zRAM или
системные службы.

## Архитектура

```text
Samsung Android / One UI
        ↓ штатный kernel и Android-драйверы
Termux + Termux:X11 (транспортный слой)
        ↓ shared tmp, без root
PRoot-Distro → официальный Fedora ARM64 image (fedora:44)
        ↓ session supervisor + D-Bus
GNOME Shell --wayland --devkit
        ↓ основной desktop протокол
Wayland-native GNOME applications
        ↘ XWayland только для legacy X11 applications
```

Termux:X11 в этой схеме — только display transport. Наличие X11-транспорта не
означает, что сессия GNOME работает как X11 desktop. Скрипт запуска сначала
проверяет Wayland через Mutter Devkit (либо старый nested режим на старом
GNOME); X11 fallback возможен только с явным
`FEDORA_ALLOW_X11=1`.

## Быстрый старт на планшете

Установите Termux и все его add-ons из одного источника подписи (F-Droid либо
GitHub; смешивать источники нельзя), затем откройте Termux. Самый удобный
вариант не требует предварительно устанавливать Git:

```bash
pkg update -y && pkg upgrade -y && pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/pluseight8/sgts11u-linux-fedora/main/scripts/bootstrap.sh -o "$PREFIX/tmp/fedora-shell-bootstrap.sh" && bash "$PREFIX/tmp/fedora-shell-bootstrap.sh"
```

Bootstrap устанавливает Git с `-y`, клонирует проект в
`$HOME/fedora-galaxy` и запускает installer. Для полностью автоматического
подтверждения Fedora installer добавьте `--yes` в конец команды bootstrap.

Команда сначала обновляет весь Termux, потому что Termux не поддерживает
частичные обновления shared libraries. Общий Android storage для bind/backup необязателен. Если он нужен, после
bootstrap запустите отдельно и дождитесь его собственного вопроса:

```bash
termux-setup-storage
```

Не вставляйте `termux-setup-storage` и следующие команды одним блоком: при
существующем `~/storage` эта команда интерактивна.

Если старый checkout после `git pull` сообщил `Permission denied`, один раз
запустите `bash ./scripts/install.sh --yes`: installer восстановит права
только у известных проектных launcher-файлов.

Для установки совместимого Termux:Boot observer (он не запускает скрытый
Fedora-процесс и не нужен при выборе Fedora Shell как Home) используйте только
после проверки ручного запуска:

```bash
bash ./scripts/install.sh --enable-boot
```

Этот Termux:Boot hook является безопасным observer и намеренно не запускает
скрытый Fedora/PRoot-процесс. После выбора Fedora Shell как Home видимая Home
Activity сама запускает Linux Mode; так не расходуется RAM в фоне и не
обходятся ограничения Android.

Инсталлятор не устанавливает APK молча и не меняет default Home app. После
ручной установки Android APK сначала завершите его первоначальный GUI-мастер;
он не меняет Android и только предлагает открыть штатный выбор Home. Для
отображения рабочего стола нужно отдельно установить совместимые APK
Termux:X11 и его пакет. Для работающего свайпа снизу оставьте в настройках
Termux:X11 параметр `Fullscreen on device display` выключенным; проект не
меняет эту Android-настройку автоматически. Полный экран можно включить
вручную, но тогда нижняя системная навигация может быть скрыта.
На Android 12+/One UI надёжный ручной порядок такой: сначала открыть APK
Termux:X11, затем выполнить `scripts/start.sh`. Android-контроллер из
`android/` делает это одной кнопкой Start после первоначальной настройки и
выдачи разрешения Termux RUN_COMMAND.

Подробности: [INSTALL.md](INSTALL.md), ограничения: [ARCHITECTURE.md](ARCHITECTURE.md),
фактические результаты: [STATUS.md](STATUS.md).

Android-контроллер находится в [android/](android/). Это обычный APK для
Home/emergency UI: он не устанавливает Termux, не получает root и не
может принудительно заменить One UI. Для запуска команд он использует
документированный Termux `RUN_COMMAND` после явного разрешения пользователя.
Его `BOOT_COMPLETED` receiver не запускает скрытый Fedora-процесс: при выборе
Fedora Shell как Home запуск выполняется только после появления видимой Home
Activity, что экономит RAM и не обходит Android background-activity policy.

## Команды

```text
scripts/install.sh       первоначальная установка Fedora и конфигурации
scripts/start.sh         запуск/переподключение display + GNOME
scripts/stop.sh          остановка сессии проекта
scripts/linux-mode.sh    ON/OFF, recovery и read-only memory status
scripts/diagnostics.sh   отчёт Android/Termux/Fedora/GPU/Wayland
scripts/update.sh        backup → checkout/packages update → повторная проверка
scripts/backup.sh        архив rootfs и host-конфигурации
scripts/restore.sh       восстановление из архива
scripts/reset.sh         удалить и заново создать только Fedora container
scripts/uninstall.sh     удалить только файлы проекта и container
```

`reset.sh` и `uninstall.sh` требуют явного подтверждения. Они никогда не
трогают пользовательские Android-файлы, One UI или системные разделы.

Для обслуживания используйте:

```text
scripts/update.sh             backup + clean checkout sync + Termux/Fedora update
scripts/update.sh --no-termux только Fedora container
scripts/update.sh --no-project не менять установленный control tree
scripts/remove.sh --dry-run   preview удаления
scripts/remove.sh              удалить Fedora Shell после подтверждения
```

Дополнительные проверки:

```text
gpu/scripts/probe-gpu.sh             Android/Termux GPU capability inventory
gpu/scripts/check-renderer.sh        Fedora GL/EGL/Vulkan/Wayland probe
gpu/scripts/measure-frame-pacing.sh  refresh settings + Wayland client proxy
input/probe-input.sh                 Android input/Termux:X11 inventory
input/keyboard-mode.sh               Linux-only keyboard focus/status (read-only)
audio/diagnose.sh                    Termux audio capability inventory
integration/android-bridge.sh        allowlisted Android API/intent client
integration/android-bridge-broker.sh local broker for Fedora-to-Android app launches
scripts/android-apps.sh              explicit GUI/Termux refresh of Fedora app entries
integration/android-memory-governor.sh read-only RAM/PSS/PSI/zRAM report
```

### Android applications from Fedora

В Linux Mode при запуске `start.sh` поднимается локальный broker без сети.
Сессия Fedora автоматически создаёт в меню GNOME пользовательские записи для
всех Android-приложений, видимых штатному read-only launcher-resolver, включая
launchable системные приложения. Это каталог запуска, а не список для
ограничения или остановки Android. Для third-party-only режима укажите
`FEDORA_ANDROID_APPS_SCOPE=user` в `~/.fedora-shell/config.env`. Обновить их можно через
пункт **Refresh Android applications** или из терминала Fedora:

```bash
fedora-android-bridge list-apps       # сторонние/user-приложения
fedora-android-bridge list-apps --all # все launchable Android-приложения
fedora-android-bridge sync-apps
```

Тот же refresh доступен кнопкой **Refresh Android apps in Fedora** в Android-
контроллере. Кнопка только передаёт фиксированную команду уже запущенному
Linux Mode и не запускает скрытый Fedora/PRoot-сеанс.

Клик запускает точный Android package через штатный resolver. Activity
показывается Android/SurfaceFlinger поверх Termux:X11; это foreground hand-off,
а не встраивание Android-окна в Wayland. Закрытие приложения/Back возвращает
предыдущую Android Activity. Если Android запрещает запуск из background,
оставьте Termux:X11 открытым и повторите клик. При ошибке перечисления старые
записи сохраняются. Функция не устанавливает, отключает, замораживает, не
выполняет force-stop и не изменяет Android-пакеты.

Автообновление включается значением `FEDORA_ANDROID_APPS_MODE=auto` или `on`;
`off` только отключает refresh каталога. Область каталога задаёт
`FEDORA_ANDROID_APPS_SCOPE=all` (по умолчанию) или `user`. Это Fedora/Termux-
предпочтение, а не Android policy.

### Клавиатура в Linux Mode

При активном Linux Mode `FEDORA_KEYBOARD_MODE=linux` задаёт профиль фокуса:
обычные аппаратные клавиши идут в сфокусированную Activity Termux:X11 и далее в
Wayland/Mutter/GNOME. Перед сочетанием нужно тапнуть по поверхности Fedora и
оставить Termux:X11 на переднем плане. В Android Mode этот профиль не работает
и Android не меняется.

Home, Back, громкость, уведомления, скриншоты, DeX и другие защищённые
системные сочетания остаются у Android SystemUI: обычное приложение не может
глобально переназначить их на Fedora через публичный SDK. Проект не использует
AccessibilityService, IME, overlay, root или изменение Android keymap. Для
нижнего свайпа оставьте `Fullscreen on device display` в Termux:X11 выключенным.
Статус проверяется без изменений Android:

```bash
bash "$HOME/.local/share/fedora-shell/input/keyboard-mode.sh" status --read-preferences
bash "$HOME/.local/share/fedora-shell/input/keyboard-mode.sh" guide
```

Подробнее и официальные ссылки: [input/README.md](input/README.md).

## Память на планшете 12 GiB

Профиль `FEDORA_MEMORY_PROFILE=auto` выбирает консервативный `low` при
обнаружении примерно 12 GiB host RAM. Он сохраняет GNOME/Wayland, не запускает
необязательные `gnome-settings-daemon`, terminal, WirePlumber, pipewire-pulse,
keyring, Tracker indexing и Evolution/GOA calendar helpers, но оставляет
изолированный небольшой PipeWire display transport: Mutter Devkit использует
его для передачи изображения даже при выключенном звуке. Также ограничивается
glibc arena growth, выключаются анимации и в low-профиле не запускается
внутренний Xwayland. Для nested Mutter автоматически выбирается виртуальный
режим 1920×1200, уменьшая compositor buffers; физическое Android-разрешение не
изменяется. Это экономит RAM и заряд без попытки подменить Android memory
manager. Перед запуском GNOME supervisor проверяет не только наличие PipeWire
socket, но и реальное подключение native client через `pw-cli`; при сбое
изолированной конфигурации есть однократный fallback на Fedora default.
Временные изменения Fedora-dconf для Tracker и logind-несовместимых GNOME
helpers сохраняются и возвращаются при завершении; после жёсткого обрыва они
восстанавливаются при следующем запуске или recovery. Android dconf/настройки
при этом не существуют в области действия проекта.

Включить конкретную возможность можно отдельно:

```bash
FEDORA_AUDIO_MODE=on FEDORA_SETTINGS_DAEMON=on \
  FEDORA_LAUNCH_TERMINAL=on bash ./scripts/start.sh
```

`FEDORA_MEMORY_PROFILE=balanced` возвращает обычный набор GNOME helpers.
Если ранее `low` отключил Tracker, верните его явно через
`FEDORA_SEARCH_MODE=on`.

Чтобы вернуть native/пользовательский виртуальный размер в low-профиле:

```bash
FEDORA_NESTED_MODE_SPECS=2960x1848 FEDORA_MEMORY_PROFILE=low bash ./scripts/start.sh
```

Для отладки необязательные ограничения можно включить точечно:
`FEDORA_NESTED_XWAYLAND=on`, `FEDORA_CALENDAR_MODE=on` или
`FEDORA_DEVKIT_PIPEWIRE_CONFIG=off`. Последний вариант возвращает обычную
Fedora PipeWire-конфигурацию и нужен только для A/B-проверки.

Linux swap не создаётся: zram/swap и reclaim принадлежат Android kernel.

Samsung RAM Plus также не включается этим проектом: это OEM-настройка Android,
которая выбирается пользователем вручную в `Настройки → Обслуживание устройства
→ Память → RAM Plus` (названия могут отличаться). Fedora Shell не вызывает
скрытые Android settings/ADB-команды, не меняет эту настройку и не обещает
«добавочную физическую RAM». Read-only отчёт показывает только доступные
косвенные `zRAM`/swap-счётчики, потому что unprivileged Termux не может надёжно
прочитать точное значение переключателя Samsung.

Для глубокого сна используется только ручной штатный список Samsung: Fedora
Shell открывает его, но не выбирает приложения и не записывает Android policy.
Официальная справка Samsung: [Sleeping apps / Deep sleeping apps](https://www.samsung.com/us/support/answer/ANS10003442/).

### Android Memory Governor: только наблюдение

Название governor не означает управление Android. Компонент не применяет
`force-stop`, AppOps, background restrictions, package disable, `settings put`,
LMKD/zRAM или kernel tuning. Он только читает доступные `/proc`, Android
`dumpsys meminfo` и PSS Fedora-процессов, сохраняет `before`/`after` снимки и
создаёт `android-policy-backup.json` с явным `androidChangesApplied=false`.
Allowlist в `config/android-memory-allowlist.json` — информационная метка для
отчётов, а не список команд для ограничения приложений. Если пакет неизвестен,
он не трогается.

В JSON-отчёте отдельно видны `MemAvailable`, cached/reclaimable память,
`SwapFree`, zRAM, PSI и счётчик major page faults; Android framework totals и
best-effort PSS system-процессов помечены своим источником. PSS
`SurfaceFlinger` не выдаётся за GPU VRAM: если драйвер не публикует безопасный
counter, раздел `gpu.memoryKiB` остаётся `null`. Поэтому отчёт помогает найти
реальный источник давления на память, но не подменяет Android LMKD.

Вложенный объект `android.ramPlus` различает `zramConfiguredKiB`,
`zramOriginalDataKiB`, `zramCompressedDataKiB` и `zramPhysicalUsedKiB`. Это
разные величины: наличие zRAM не доказывает, что включён RAM Plus, а отсутствие
доступа к sysfs не доказывает обратное. Android остаётся владельцем LMKD,
CachedAppOptimizer, zRAM и reclaim; цель Linux Focused — уменьшить именно
Fedora-side расход общей физической RAM, а не бессмысленно «чистить» Android.

В отчёт также добавляется `recommendations`: это объяснения состояния и
безопасные Fedora-side подсказки (например, сначала закрыть тяжёлое Fedora
приложение при высоком PSI). Они не являются командами управления Android и
не запускают `force-stop`, AppOps, очистку cache или изменение zRAM.

В Android-контроллере кнопка `Memory` сначала показывает быстрый
`ActivityManager`-снимок, а `Снять полный отчёт` возвращает этот read-only JSON
в отдельное прокручиваемое окно GUI: host/Android/Fedora/GNOME/Mutter,
PipeWire, zRAM/swap и PSI видны вместе с флагами доступности. Недоступные
счётчики показываются как `unknown`/`null`, а не превращаются в придуманные
точные значения.

Профили `Balanced`, `Linux Focused` и `Maximum Linux` меняют только Fedora-side
helpers, буферы nested compositor и запуск необязательных Fedora служб. Для
устройства с 12 GiB рекомендован `Linux Focused`; `Maximum Linux` — явный
Fedora-only режим с виртуальным nested-буфером 1600×1000 и более строгим
ограничением allocator fragmentation. Он не означает агрессивное управление
Android.

## Что ещё не обещано

PRoot не предоставляет настоящий kernel root, systemd PID 1, cgroups,
network namespaces или FUSE. Поэтому проект запускает session supervisor и
обычные user processes, а не имитирует полноценную bare-metal Fedora.

GPU через `virglrenderer-android`/`virpipe` и альтернативный Zink/Vulkan путь
являются экспериментальными для Mali/Immortalis. В режиме `auto` проект всегда
выбирает стабильный `llvmpipe`; VirGL устанавливается только с
`--experimental-gpu` и запускается лишь явным `FEDORA_GPU_MODE=virpipe`. Пока
`glxinfo -B`, `eglinfo`, `vulkaninfo`,
Mutter renderer и frame-pacing не проверены на конкретном устройстве, итоговый
статус остаётся `UNTESTED` или `PARTIAL`; `llvmpipe`, `softpipe` и `lavapipe`
не считаются аппаратным ускорением.

S Pen pressure/tilt, Android camera, Wi-Fi/Bluetooth UI, global brightness,
clipboard в фоне и автозапуск после boot имеют Android permission/background
ограничения. Для них предусмотрены read-only probes и user-triggered intents с
честным `ANDROID-BRIDGED` статусом, но не фиктивные Linux devices и не скрытые
изменения Android.

## Лицензия

Код проекта распространяется по MIT License. Текущая реализация не включает
сторонние binary blobs, proprietary GPU libraries или APK Termux:X11.
