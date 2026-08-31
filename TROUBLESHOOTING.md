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

Сначала сохраните диагностику:

```bash
./scripts/diagnostics.sh --full
```

Логи проекта находятся в `$HOME/.fedora-shell/logs/`. Не публикуйте полный
`getprop`/`termux-info` без удаления serial, IMEI, SSID и user paths.

## Чёрный экран

1. Убедитесь, что APK Termux:X11 и package `termux-x11-nightly` одной версии и
   одного signing source.
2. Откройте Termux:X11 вручную один раз.
3. Попробуйте другой display:

   ```bash
   FEDORA_DISPLAY=:1 ./scripts/start.sh
   ```

4. Для проблем самого X transport используйте `TERMUX_X11_LEGACY_DRAWING=1`
   только как диагностику.
5. Проверьте `logs/termux-x11.log` и `logs/fedora-session.log`.

Не включайте pure X11 как постоянное решение до проверки Wayland.

## GNOME не запускается

Проверьте, есть ли в текущем Fedora build nested option:

```bash
./scripts/diagnostics.sh --fedora
```

`gnome-shell --nested --wayland` зависит от версии GNOME. Если option удалён,
это blocker nested target, а не повод silently объявить X11 рабочим. Сначала
зафиксируйте лог, проверьте upstream GNOME/Mutter и только затем временно
используйте:

```bash
FEDORA_ALLOW_X11=1 ./scripts/start.sh
```

Состояние всё равно должно оставаться `PARTIAL`, пока Wayland не восстановлен.

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

## PRoot/D-Bus/systemd ошибки

Не запускайте `systemctl` как доказательство исправности. PRoot не даёт
настоящего PID 1/systemd и cgroups. Используйте `fedora-session`, который
запускает конкретные user processes и D-Bus session bus.

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
