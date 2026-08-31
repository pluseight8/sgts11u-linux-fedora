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

Аппаратный планшет в текущем окружении не подключён. Поэтому `STATUS.md` не
содержит неподтверждённых заявлений `WORKING`: фактические `getprop`, GPU,
touch, S Pen, audio, refresh pacing и suspend/resume нужно собрать на самом
устройстве.

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
scripts/update.sh        backup → dnf update → повторная проверка
scripts/backup.sh        архив rootfs и host-конфигурации
scripts/restore.sh       восстановление из архива
scripts/reset.sh         удалить и заново создать только Fedora container
scripts/uninstall.sh     удалить только файлы проекта и container
```

`reset.sh` и `uninstall.sh` требуют явного подтверждения. Они никогда не
трогают пользовательские Android-файлы, One UI или системные разделы.

Для обслуживания используйте:

```text
scripts/update.sh             backup + Termux/Fedora package update
scripts/update.sh --no-termux только Fedora container
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

## Что ещё не обещано

PRoot не предоставляет настоящий kernel root, systemd PID 1, cgroups,
network namespaces или FUSE. Поэтому проект запускает session supervisor и
обычные user processes, а не имитирует полноценную bare-metal Fedora.

GPU через `virglrenderer-android`/`virpipe` и альтернативный Zink/Vulkan путь
являются экспериментальными для Mali/Immortalis. В режиме `auto` при отсутствии
virgl проект выбирает стабильный `llvmpipe`, чтобы GNOME не зависел от
непроверенного Android/Mesa backend. Пока `glxinfo -B`, `eglinfo`, `vulkaninfo`,
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
