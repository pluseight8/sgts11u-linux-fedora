# Troubleshooting

## Жёсткий Android-контракт

Проект не меняет Android, One UI или их политики. В Linux Mode разрешены
только запуск и остановка собственных Termux/PRoot/Fedora процессов, чтение
диагностики и пользовательский выбор Home через штатный Android UI. Не
используйте и не добавляйте `settings put`, AppOps, `am force-stop`, `pm
disable`, убийство системных Android-процессов, очистку page cache или
изменение LMKD/zRAM. Для Android Mode пользователь выбирает `One UI Home` в
`Default apps → Home app`.

`android-memory-governor.sh` и кнопка `Memory` только читают RAM/PSS/PSI/zRAM
и сохраняют снимки. Allowlist не ограничивает Android-приложения.

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

## `Permission denied` after `git pull`

If Git shows a mode change such as `755 => 644`, run the installer through
`bash` once so it can repair the project-owned launcher bits and resync the
installed control tree:

```bash
cd "$HOME/fedora-galaxy"
bash ./scripts/install.sh --yes --memory-profile low
```

The installer repairs only known Fedora Shell launchers. Do not use a
recursive `chmod` over `$HOME` or Termux's whole prefix.

## Fedora сообщает `No match for argument: xorg-x11-server-utils`

Это старое/недоступное имя X11-пакета для Fedora 44 на ARM64, а не причина
удалять уже созданный container. Обновите checkout и продолжите установку:

```bash
cd "$HOME/fedora-galaxy"
git pull --ff-only
bash ./scripts/install.sh --yes
```

Installer больше не требует этот пакет для Wayland/GNOME. Недоступные
дополнительные приложения GNOME пропускаются, а обязательные компоненты
останавливают установку только при настоящей ошибке транзакции.

Предупреждение PRoot о `/tmp/.X11-unix` во время установки не является
фатальным: Termux:X11 ещё не был запущен. Перед первым запуском откройте
Termux:X11 один раз либо используйте `bash ./scripts/start.sh`, который запускает
его сам.

Сначала сохраните диагностику:

```bash
bash ./scripts/diagnostics.sh --full
```

Логи проекта находятся в `$HOME/.fedora-shell/logs/`. Не публикуйте полный
`getprop`/`termux-info` без удаления serial, IMEI, SSID и user paths.

## Чёрный экран

1. Убедитесь, что APK Termux:X11 и package `termux-x11-nightly` одной версии и
   одного signing source.
2. Откройте Termux:X11 вручную один раз. Автоматический `am start` может быть
   запрещён Android 16/One UI политикой запуска background activity; поэтому
   `FEDORA_TERMUX_X11_AUTO_OPEN=auto` теперь распознаёт Android 12+ и не делает
   заведомо бесполезный вызов. Для старого устройства можно явно проверить
   автоматический путь через `FEDORA_TERMUX_X11_AUTO_OPEN=on`.
3. Если поверхность чёрная или виден только курсор, перезапустите через
   compatibility drawing:

   ```bash
   bash "$HOME/.local/share/fedora-shell/scripts/linux-mode.sh" recover || true
   bash "$HOME/.local/share/fedora-shell/scripts/linux-mode.sh" enable \
     --profile linux-focused
   ```

   Если используется checkout с потерянными executable bits, именно `bash`
   здесь важно. Прямой эквивалент: `bash ./scripts/start.sh --legacy-drawing`.
   Сначала вручную оставьте Activity Termux:X11 открытой.

   В профиле `low` PipeWire display transport всё равно запускается: это не
   звук, а обязательный канал Mutter Devkit для вывода вложенного экрана.
   Полный звук при этом остаётся выключенным.

   Если в журнале есть `PipeWire display transport is ready`, а затем
   `mutter-devkit: Failed to connect pipewire context`, обновите установленное
   дерево: новая версия использует отдельную конфигурацию PipeWire только для
   Devkit, добавляет `pipewire-utils`, проверяет реальное подключение через
   `pw-cli`, фиксирует `PIPEWIRE_RUNTIME_DIR`/`PIPEWIRE_REMOTE`/`PIPEWIRE_CORE`
   и удаляет зависшие сокеты перед новым запуском. При ошибке изолированной
   конфигурации выполняется один проверенный fallback на Fedora default:

   ```bash
   cd "$HOME/fedora-galaxy"
   git pull --ff-only
   bash ./scripts/install.sh --yes --memory-profile low
   ```

   Затем полностью откройте APK Termux:X11 вручную и запустите:

   ```bash
   FEDORA_TERMUX_X11_AUTO_OPEN=off \
   FEDORA_MEMORY_PROFILE=low \
   FEDORA_GPU_MODE=software \
   FEDORA_AUDIO_MODE=off \
   FEDORA_PORTAL_MODE=off \
   FEDORA_NESTED_XWAYLAND=off \
   FEDORA_CALENDAR_MODE=off \
   FEDORA_DEVKIT_GDK_BACKEND=x11 \
   FEDORA_DEVKIT_PIPEWIRE=on \
   FEDORA_DEVKIT_DEBUG=1 \
   FEDORA_NESTED_MODE_SPECS=2048x1280 \
   bash "$HOME/.local/share/fedora-shell/scripts/start.sh" --legacy-drawing
   ```

   Если проверка PipeWire остановила запуск, причина будет в
   `/tmp/fedora-runtime/pipewire-probe.log` внутри Fedora и в
   `$HOME/.fedora-shell/logs/fedora-session.log` на стороне Termux. Не
   отключайте `FEDORA_DEVKIT_PIPEWIRE` в рабочем Wayland-сеансе: Mutter Devkit
   использует этот native PipeWire transport для показа вложенного экрана.

   Если в логе встречается `stale /run/systemd/seats`, новая версия проверяет
   этот путь через root только внутри Fedora/PRoot, временно переименовывает
   ровно guest-маркер и восстанавливает его после выхода. Это не Android
   `/run`, не mount Android и не изменение systemd host. В full report есть
   read-only проверка `Fedora systemd marker`.

   GNOME 50 также может включать Fedora-local screen-time history. В PRoot
   нет systemd/logind, поэтому перед запуском Shell эта совместимость
   отключается только в Fedora dconf; Android Digital Wellbeing и Android
   parental controls не затрагиваются. Fedora-local system-bus compatibility
   endpoint предотвращает startup abort при создании `Gio.DBus.system`, но не
   симулирует `org.freedesktop.login1`; его `ServiceUnknown` после этого
   ожидаем.

   Этот режим рекомендован upstream Termux:X11 для устройств, где обычный
   drawing даёт чёрную поверхность.
4. Попробуйте другой display:

   ```bash
   FEDORA_DISPLAY=:1 bash ./scripts/start.sh
   ```

5. Переменную `TERMUX_X11_LEGACY_DRAWING=1` теперь тоже можно использовать
   вместо CLI-флага.
6. Проверьте `logs/termux-x11.log` и `logs/fedora-session.log`.

Не включайте pure X11 как постоянное решение до проверки Wayland.

## GNOME не запускается

Проверьте, есть ли в текущем Fedora build nested option:

```bash
bash ./scripts/diagnostics.sh --fedora
```

`gnome-shell --nested --wayland` зависит от версии GNOME. В GNOME 49+ этот
option удалён, и нужен Mutter Devkit:

```bash
cd "$HOME/fedora-galaxy"
bash ./scripts/install.sh --yes
```

Современный путь — `gnome-shell --wayland --devkit`; пакет `mutter-devkit`
устанавливается автоматически. Это всё ещё Wayland desktop, показанный через
внешний Termux:X11 transport. Если Devkit тоже не стартует, зафиксируйте лог,
проверьте upstream GNOME/Mutter и только затем временно
используйте:

```bash
FEDORA_ALLOW_X11=1 bash ./scripts/start.sh
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
FEDORA_GPU_MODE=software FEDORA_PORTAL_MODE=off bash ./scripts/start.sh
```

Если после этого Shell работает, оставьте software mode. VirGL проверяйте
отдельно после `bash ./scripts/install.sh --experimental-gpu`, затем
`FEDORA_GPU_MODE=virpipe .../start.sh`; это не считается аппаратным
ускорением без подтверждённого renderer.

## Renderer = llvmpipe/softpipe/lavapipe

Это software rendering. Выполните:

```bash
bash ./gpu/scripts/probe-gpu.sh
bash ./scripts/diagnostics.sh --fedora
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
bash ./scripts/diagnostics.sh --full --redact
```

На 12 GiB `auto` выбирает `low`: terminal, WirePlumber, pipewire-pulse, keyring,
Tracker, settings daemon и Evolution/GOA calendar helpers не стартуют
автоматически, а изолированный минимальный PipeWire display transport остаётся
для Mutter Devkit. Внутренний Xwayland отключён, а nested monitor обычно
работает в 1920×1200. Это ожидаемая оптимизация. Включайте только то, что нужно для
текущей задачи:

```bash
FEDORA_AUDIO_MODE=on bash ./scripts/start.sh
FEDORA_SETTINGS_DAEMON=on FEDORA_LAUNCH_TERMINAL=on bash ./scripts/start.sh
```

Если нужен только GNOME Devkit без звука, ничего дополнительно включать не
нужно. `FEDORA_DEVKIT_PIPEWIRE=off` предназначен только для отладки и почти
гарантированно отключит видимый Devkit-сеанс.

Если нужен обычный полный desktop-профиль:

```bash
FEDORA_MEMORY_PROFILE=balanced bash ./scripts/start.sh
# восстановить Tracker после low-профиля только при необходимости:
FEDORA_MEMORY_PROFILE=balanced FEDORA_SEARCH_MODE=on bash ./scripts/start.sh
```

Native virtual mode можно вернуть отдельно, не меняя Android display:

```bash
FEDORA_MEMORY_PROFILE=low FEDORA_NESTED_MODE_SPECS=2960x1848 bash ./scripts/start.sh
```

Не создавайте swap-файл внутри PRoot: это не добавит Android kernel swap и
может только занять место/ухудшить latency.

### RAM Plus

Если нужна именно функция Samsung RAM Plus, включайте её только вручную в
Android Settings: `Настройки → Обслуживание устройства → Память → RAM Plus`.
Fedora Shell намеренно не имеет команды для её включения, выключения или
изменения размера: это нарушило бы требование «Android не модифицировать».
Функция использует внутреннее хранилище как виртуальную память, поэтому не
является дополнительной физической RAM и может повысить задержки при давлении
на память. Поле `android.ramPlus` в отчёте — диагностическое: `setting` обычно
`not-readable`, а zRAM/sysfs-поля показывают только то, что разрешил прочитать
Termux. Не интерпретируйте `zramObserved=true` как доказательство включённого
RAM Plus.

Для read-only измерения общей памяти и Fedora PSS выполните:

```bash
bash "$HOME/.local/share/fedora-shell/scripts/linux-mode.sh" memory
```

Снимки `memory-before.json`, `memory-after.json` и `memory-latest.json`
сохраняются в `$HOME/.fedora-shell/state/`. Android сам управляет cached-app
freezing, reclaim и zRAM; проект не выполняет RAM-cleaner действий. В отчёте
также есть Cached/SReclaimable/SwapFree, PSI, major faults, Android dumpsys
totals, best-effort system/SurfaceFlinger PSS и отдельный `gpu.memoryKiB=null`,
если точный GPU counter недоступен. Не складывайте эти категории как точный
итог: PSS и framework totals используют разные модели учёта.

## PRoot/D-Bus/systemd ошибки

Не запускайте `systemctl` как доказательство исправности. PRoot не даёт
настоящего PID 1/systemd и cgroups. Используйте `fedora-session`, который
запускает конкретные user processes, private D-Bus session bus и отдельный
Fedora-local system-bus compatibility endpoint. `DBUS_SYSTEM_BUS_ADDRESS`
указывает только на временный сокет внутри `$FEDORA_SESSION_RUNTIME`; Android
system bus не наследуется, не подменяется и не изменяется. Compatibility bus не
имеет service directories, поэтому logind, UPower, RTKit и другие privileged
system services по-прежнему недоступны, а их `ServiceUnknown` предупреждения
ожидаемы. Если в guest остался только файл
`/run/systemd/seats`, supervisor временно прячет именно этот stale marker,
чтобы GNOME выбрал dummy login manager, и восстанавливает его при выходе.

Для GNOME 50 ошибка `Gjs-CRITICAL ... timeLimitsManager.js` с последующим
`free(): invalid pointer` означала не нехватку RAM, а необработанную попытку
открыть отсутствующую system D-Bus шину в PRoot. После обновления в логе должна
появиться строка `Fedora-private system D-Bus compatibility bus is ready`; при
этом privileged service names всё равно останутся отсутствующими намеренно.

Сообщение `fuse: failed to open /dev/fuse` относится к document portal:
Android/PRoot обычно не может предоставить FUSE mount. В
`FEDORA_PORTAL_MODE=auto` порталы пропускаются автоматически, а
`GIO_USE_VFS=local` предотвращает лишний GVFS. GNOME или Mutter могут всё ещё
проверить portal через D-Bus; при `FEDORA_PORTAL_MODE=off` проект не создаёт
фальшивые portal-сервисы, поэтому ожидаем обычный `ServiceUnknown` без запуска
FUSE или portal-процесса. Широкая D-Bus-блокировка и искусственный `AccessDenied`
не являются нормальным путём. Принудительный
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

## Android overlays и выход из Fedora

Панель громкости, шторка уведомлений и жесты/кнопки Back, Home и Overview
принадлежат Android SystemUI. Fedora Shell не может отключить защищённые
системные окна, поэтому кратковременная панель громкости или шторка поверх
рабочего стола — штатное поведение Android, а не Fedora-ошибка.

Если свайп снизу вверх не работает именно поверх рабочего стола, откройте
Termux:X11 → Preferences и вручную выключите `Fullscreen on device display`.
Видимая поверхность рабочего стола принадлежит отдельному Termux:X11 APK;
контроллер Fedora не может изменить его Window flags. После этого Android
сохраняет нижнюю gesture/navigation область: свайп снизу вверх открывает Home,
с удержанием — Overview, свайп от края — Back. Никакие Android settings,
SystemUI или пакеты проект при этом не меняет.

## Android apps/brightness/clipboard

Android 12+ ограничивает background activity launches, Android 11+ использует
scoped storage, а clipboard может быть недоступен background service. Выдайте
только нужные runtime/special permissions и используйте SAF. `Fedora Shell`
может открыть Android Settings и показать системный запрос `ROLE_HOME`, но не
назначает себя Home app и не возвращает One UI молча. Для Android Mode выберите
`One UI Home` вручную в `Home app`.

## Восстановление

```bash
bash ./scripts/stop.sh
bash ./scripts/restore.sh /storage/emulated/0/FedoraBackups/fedora-s11u-*.tar.xz
```

Если Fedora повреждена и backup не нужен:

```bash
bash ./scripts/reset.sh
```

Это удаляет данные **только внутри Fedora container**. Для полного удаления
проекта:

```bash
bash ./scripts/uninstall.sh
```

После удаления для обычного Android выберите One UI Home в системных настройках.

Если запускаете через Android APK и команда не доходит до Termux, проверьте
`com.termux.permission.RUN_COMMAND`, параметр
`allow-external-apps=true`, доступ Termux к фоновому выполнению и одинаковый
signing source для Termux add-ons. APK не может обходить эти Android policy.
