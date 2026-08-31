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

Для автоматического запуска через Termux:Boot используйте только после
проверки ручного запуска:

```bash
./scripts/install.sh --enable-boot
```

Инсталлятор не устанавливает APK молча и не меняет default Home app. Для
получения fullscreen нужно отдельно установить совместимые APK Termux:X11 и
его пакет, затем включить fullscreen в настройках Termux:X11.

Подробности: [INSTALL.md](INSTALL.md), ограничения: [ARCHITECTURE.md](ARCHITECTURE.md),
фактические результаты: [STATUS.md](STATUS.md).

Android-контроллер находится в [android/](android/). Это обычный опциональный
APK для Home/emergency UI: он не устанавливает Termux, не получает root и не
может принудительно заменить One UI. Для запуска команд он использует
документированный Termux `RUN_COMMAND` после явного разрешения пользователя.

## Команды

```text
scripts/install.sh       первоначальная установка Fedora и конфигурации
scripts/start.sh         запуск/переподключение display + GNOME
scripts/stop.sh          остановка сессии проекта
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
audio/diagnose.sh                    Termux audio capability inventory
integration/android-bridge.sh        allowlisted Android API/intent client
```

## Память на планшете 12 GiB

Профиль `FEDORA_MEMORY_PROFILE=auto` выбирает консервативный `low` при
обнаружении примерно 12 GiB host RAM. Он сохраняет GNOME/Wayland, но не
запускает без запроса необязательные `gnome-settings-daemon`, terminal,
PipeWire и Tracker indexing; также ограничивает glibc arena growth и выключает
анимации. Для nested Mutter автоматически выбирается виртуальный режим
2560×1600, уменьшая compositor/Xwayland buffers; физическое Android-разрешение
не изменяется. Это экономит RAM и заряд без попытки подменить Android memory
manager.

Включить конкретную возможность можно отдельно:

```bash
FEDORA_AUDIO_MODE=on FEDORA_SETTINGS_DAEMON=on \
  FEDORA_LAUNCH_TERMINAL=on ./scripts/start.sh
```

`FEDORA_MEMORY_PROFILE=balanced` возвращает обычный набор GNOME helpers.
Если ранее `low` отключил Tracker, верните его явно через
`FEDORA_SEARCH_MODE=on`.

Чтобы вернуть native/пользовательский виртуальный размер в low-профиле:

```bash
FEDORA_NESTED_MODE_SPECS=2960x1848 FEDORA_MEMORY_PROFILE=low ./scripts/start.sh
```

Linux swap не создаётся: zram/swap и reclaim принадлежат Android kernel.

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
ограничения. Для них предусмотрены API-заготовки и честный `ANDROID-BRIDGED`
статус, но не фиктивные Linux devices.

## Лицензия

Код проекта распространяется по MIT License. Текущая реализация не включает
сторонние binary blobs, proprietary GPU libraries или APK Termux:X11.
