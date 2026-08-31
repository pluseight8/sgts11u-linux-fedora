# Troubleshooting

## Termux asks `Y/n` and then aborts

`termux-setup-storage` is interactive when `~/storage` already exists. Run it
alone, answer `y`, and wait for the shell prompt before entering another
command. The bootstrap avoids this interaction entirely and also uses
non-interactive `pkg` flags:

```bash
pkg update -y && pkg upgrade -y && pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/pluseight8/sgts11u-linux-fedora/main/scripts/bootstrap.sh -o "$PREFIX/tmp/fedora-shell-bootstrap.sh" && bash "$PREFIX/tmp/fedora-shell-bootstrap.sh"
```

The message about selecting a Termux mirror is informational if package lists
are fetched successfully. Use `termux-change-repo` only when the update really
fails.

## `CANNOT LINK EXECUTABLE "curl"`

This means that Termux has a partial upgrade: for example, `curl`/`libcurl`
was updated while OpenSSL or another shared dependency remained old. Repair
the rolling-release environment before downloading anything else:

```bash
pkg update -y
pkg upgrade -y
curl --version
```

If the full upgrade reports broken dependencies, run the package repair once
and repeat the upgrade:

```bash
apt --fix-broken install -y
pkg upgrade -y
```

Do not install only `curl`, `libcurl` or `libngtcp2` in a stale Termux
environment; Termux documents that partial upgrades are unsupported.

## Fedora сообщает `No match for argument: xorg-x11-server-utils`

Это старое/недоступное имя X11-пакета для Fedora 44 на ARM64, а не причина
удалять уже созданный container. Обновите checkout и продолжите установку:

```bash
cd "$HOME/fedora-galaxy"
git pull --ff-only
./scripts/install.sh --yes
```

Installer больше не требует этот пакет для Wayland/GNOME. Недоступные
дополнительные приложения GNOME пропускаются, а обязательные компоненты
останавливают установку только при настоящей ошибке транзакции.

Предупреждение PRoot о `/tmp/.X11-unix` во время установки не является
фатальным: Termux:X11 ещё не был запущен. Перед первым запуском откройте
Termux:X11 один раз либо используйте `./scripts/start.sh`, который запускает
его сам.

Сначала сохраните диагностику:

```bash
./scripts/diagnostics.sh --full
```

Логи проекта находятся в `$HOME/.fedora-shell/logs/`. Не публикуйте полный
`getprop`/`termux-info` без удаления serial, IMEI, SSID и user paths.

## Чёрный экран

1. Убедитесь, что APK Termux:X11 и package `termux-x11-nightly` одной версии и
   одного signing source.
2. Откройте Termux:X11 вручную один раз. Автоматический `am start` может быть
   запрещён Android 16/One UI политикой запуска background activity.
3. Если поверхность чёрная или виден только курсор, перезапустите через
   compatibility drawing:

   ```bash
   ./scripts/stop.sh --yes
   FEDORA_GPU_MODE=software FEDORA_PORTAL_MODE=off \
     ./scripts/start.sh --legacy-drawing
   ```

   Этот режим рекомендован upstream Termux:X11 для устройств, где обычный
   drawing даёт чёрную поверхность.
4. Попробуйте другой display:

   ```bash
   FEDORA_DISPLAY=:1 ./scripts/start.sh
   ```

5. Переменную `TERMUX_X11_LEGACY_DRAWING=1` теперь тоже можно использовать
   вместо CLI-флага.
6. Проверьте `logs/termux-x11.log` и `logs/fedora-session.log`.

Не включайте pure X11 как постоянное решение до проверки Wayland.

## GNOME не запускается

Проверьте, есть ли в текущем Fedora build nested option:

```bash
./scripts/diagnostics.sh --fedora
```

`gnome-shell --nested --wayland` зависит от версии GNOME. В GNOME 49+ этот
option удалён, и нужен Mutter Devkit:

```bash
cd "$HOME/fedora-galaxy"
./scripts/install.sh --yes
```

Современный путь — `gnome-shell --wayland --devkit`; пакет `mutter-devkit`
устанавливается автоматически. Это всё ещё Wayland desktop, показанный через
внешний Termux:X11 transport. Если Devkit тоже не стартует, зафиксируйте лог,
проверьте upstream GNOME/Mutter и только затем временно
используйте:

```bash
FEDORA_ALLOW_X11=1 ./scripts/start.sh
```

Состояние всё равно должно оставаться `PARTIAL`, пока Wayland не восстановлен.

### `gnome-shell ... Aborted` или `SIGABRT`

Если Wayland-сокет создаётся, а затем появляется `Aborted`, это уже не ошибка
выбора display mode: GNOME Shell аварийно завершился после инициализации.
Новый supervisor оставляет причину в журнале и больше не маскирует её общим
сообщением. Посмотрите:

```bash
tail -n 120 "$HOME/.fedora-shell/logs/fedora-session.log"
```

Штатный `auto` всегда использует `llvmpipe`, даже если optional
`virgl_test_server_android` установлен. Для явного повторного теста с
минимальным числом необязательных служб:

```bash
FEDORA_GPU_MODE=software FEDORA_PORTAL_MODE=off ./scripts/start.sh
```

Если после этого Shell работает, оставьте software mode. VirGL проверяйте
отдельно после `./scripts/install.sh --experimental-gpu`, затем
`FEDORA_GPU_MODE=virpipe .../start.sh`; это не считается аппаратным
ускорением без подтверждённого renderer.

## Renderer = llvmpipe/softpipe/lavapipe

Это software rendering. Выполните:

```bash
./gpu/scripts/probe-gpu.sh
./scripts/diagnostics.sh --fedora
```

Затем проверьте:

```bash
glxinfo -B
eglinfo
vulkaninfo --summary
```

Не устанавливайте Qualcomm Turnip и не используйте Adreno-инструкции. Для
Immortalis сначала проверяется host Vulkan, затем virpipe; Zink/Android Vulkan
wrapper остаётся experimental.

## Мало свободной RAM / 12 GiB

Проверьте выбранный профиль и RSS процессов:

```bash
./scripts/diagnostics.sh --full --redact
```

На 12 GiB `auto` выбирает `low`: terminal, PipeWire, Tracker и settings daemon
не стартуют автоматически, а nested monitor обычно работает в 2560×1600.
Это ожидаемая оптимизация. Включайте только то, что нужно для текущей задачи:

```bash
FEDORA_AUDIO_MODE=on ./scripts/start.sh
FEDORA_SETTINGS_DAEMON=on FEDORA_LAUNCH_TERMINAL=on ./scripts/start.sh
```

Если нужен обычный полный desktop-профиль:

```bash
FEDORA_MEMORY_PROFILE=balanced ./scripts/start.sh
# восстановить Tracker после low-профиля только при необходимости:
FEDORA_MEMORY_PROFILE=balanced FEDORA_SEARCH_MODE=on ./scripts/start.sh
```

Native virtual mode можно вернуть отдельно, не меняя Android display:

```bash
FEDORA_MEMORY_PROFILE=low FEDORA_NESTED_MODE_SPECS=2960x1848 ./scripts/start.sh
```

Не создавайте swap-файл внутри PRoot: это не добавит Android kernel swap и
может только занять место/ухудшить latency.

## PRoot/D-Bus/systemd ошибки

Не запускайте `systemctl` как доказательство исправности. PRoot не даёт
настоящего PID 1/systemd и cgroups. Используйте `fedora-session`, который
запускает конкретные user processes и private D-Bus session bus. Для GNOME
50+ supervisor также направляет `DBUS_SYSTEM_BUS_ADDRESS` на этот private bus:
это совместимый endpoint для инициализации Shell, а не настоящий system bus.
Поэтому сервисы logind, UPower, RTKit и другие privileged system services
по-прежнему недоступны; их предупреждения ожидаемы.

Сообщение `fuse: failed to open /dev/fuse` относится к document portal:
Android/PRoot обычно не может предоставить FUSE mount. В
`FEDORA_PORTAL_MODE=auto` порталы пропускаются автоматически, а
`GIO_USE_VFS=local` предотвращает лишний GVFS. GNOME может всё ещё попытаться
проверить portal через D-Bus, поэтому в логах допустимы `AccessDenied` или
`ServiceUnknown`; это не должно останавливать desktop. Принудительный
`FEDORA_PORTAL_MODE=on` имеет смысл только после
проверки доступности FUSE и может снова вернуть эту ошибку.

## Нет audio

Проверьте наличие Termux PulseAudio backend и права notifications/battery:

```bash
./audio/diagnose.sh
```

Audio должен идти через Android/Termux, а не через прямой доступ Fedora к
Samsung codec. Динамики, Bluetooth и USB проверяются отдельно.

## Touch/S Pen

Termux:X11 touchpad/simulated touchscreen gestures дают базовую эмуляцию, но
не гарантируют pressure/tilt/hover. Зафиксируйте:

```text
tap, double-tap, long press, two-finger scroll/right-click,
keyboard modifiers, S Pen position/pressure/hover/tilt
```

в `STATUS.md` только после реального теста. Не называйте mouse emulation
Wayland tablet integration.

## Android apps/brightness/clipboard

Android 12+ ограничивает background activity launches, Android 11+ использует
scoped storage, а clipboard может быть недоступен background service. Выдайте
только нужные runtime/special permissions и используйте SAF. `Fedora Shell`
может открыть Android Settings, но не может privileged способом принудительно
назначить себя Home app или автоматически вернуть One UI.

## Восстановление

```bash
./scripts/stop.sh
./scripts/restore.sh /storage/emulated/0/FedoraBackups/fedora-s11u-*.tar.xz
```

Если Fedora повреждена и backup не нужен:

```bash
./scripts/reset.sh
```

Это удаляет данные **только внутри Fedora container**. Для полного удаления
проекта:

```bash
./scripts/uninstall.sh
```

После удаления для обычного Android выберите One UI Home в системных настройках.

Если запускаете через Android APK и команда не доходит до Termux, проверьте
`com.termux.permission.RUN_COMMAND`, параметр
`allow-external-apps=true`, доступ Termux к фоновому выполнению и одинаковый
signing source для Termux add-ons. APK не может обходить эти Android policy.
