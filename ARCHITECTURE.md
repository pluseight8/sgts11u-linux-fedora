# Архитектура и решения

Дата среза исследования: **2026-09-02**.

## 1. Границы безопасности

| Слой | Решение | Почему |
| --- | --- | --- |
| Boot chain | не изменяется | сохраняются AVB, OTA, Knox и штатное восстановление |
| Kernel | штатный Samsung/Android | нет custom kernel, модулей и риска brick |
| Privileges | обычный Termux UID | root не является предусловием |
| Linux userspace | официальный Fedora ARM64 OCI image | нет случайных rootfs и чужих binary blobs |
| Isolation | PRoot-Distro | обратимо, но это path translation, а не security sandbox |
| Init | Android init снаружи; `fedora-session` внутри | systemd PID 1 в PRoot ненадёжен |
| Hardware | Android APIs/Termux APIs | Fedora не притворяется владельцем Wi-Fi/codec/ISP/GPU nodes |

PRoot-Distro прямо документирует отсутствие настоящего root, systemd/OpenRC,
cgroups, kernel namespaces, FUSE и real filesystem mounts. Это влияет на
Flatpak, NetworkManager hardware control, GDM/logind, udev и некоторые GNOME
services. Проект не скрывает эти ограничения.

## 2. Display priority

```text
1. Direct Android Surface → native Wayland compositor       (future adapter)
2. Mutter/GNOME Wayland with Android-compatible backend      (probe)
3. Nested GNOME Shell/Mutter Wayland                        (current target)
4. Weston/other nested Wayland transport                    (not enabled)
5. Termux:X11 transport → nested GNOME Wayland              (current transport)
6. XWayland for legacy applications                         (allowed)
7. Full X11 GNOME session                                   (explicit temporary fallback)
```

На штатном Android наиболее проверенным публичным транспортом остаётся
Termux:X11. Его README описывает запуск с `--shared-tmp` внутри PRoot и
touchpad/simulated-touchscreen gestures. Поэтому текущий запуск выглядит так:

```text
Android Surface
  → Termux:X11 X server window
  → Mutter Devkit viewer
  → gnome-shell --wayland --devkit
  → Wayland applications
```

Это не native KMS/DRM session: Mutter не получает `/dev/dri`, не управляет
панелью напрямую и не может гарантировать 120 Hz. `FEDORA_ALLOW_X11=1`
разрешает исключительно диагностический fallback, если конкретный Fedora/GNOME
build больше не содержит nested Wayland option.

## 3. Fedora и PRoot

Выбран `fedora:44` с `--architecture aarch64`. На дату исследования Fedora 44
является текущим стабильным релизом, а Fedora Workstation 44 поставляет GNOME
50. PRoot-Distro подтягивает OCI manifest для архитектуры хоста и проверяет
SHA-256 каждого слоя. Это безопаснее непроверенного tarball, но tag `fedora:44`
не является immutable digest: установочный отчёт сохраняет фактический
manifest/image metadata, а `VERSIONS.md` не подменяет этот отчёт заранее.

В Fedora ставятся GNOME Shell/Mutter, Mutter Devkit и базовые GNOME applications. GDM, systemd
PID 1 и kernel-facing services не запускаются. `fedora-session` вручную
создаёт D-Bus session bus и Fedora-local system-bus compatibility endpoint без
service activation, запускает минимальный PipeWire transport (и только при
необходимости WirePlumber/PulseAudio) и затем GNOME Shell nested. Compatibility
endpoint нужен GNOME 50 для `Gio.DBus.system`; он не является Android bus alias и
не предоставляет logind/PolicyKit/UPower/GDM. Desktop portals запускаются только
если Android/PRoot позволяет открыть `/dev/fuse`.

## 4. GPU

### Подтверждённая гипотеза

```text
Fedora GL client
  → Mesa virpipe
  → virgl_test_server_android (Termux)
  → Android GLES / hardware driver
  → Termux:X11 output
```

Это путь совместимости, а не native GPU passthrough. У него есть копирования и
latency. `gpu/scripts/probe-gpu.sh` проверяет наличие Vulkan/virgl на Termux,
а `gpu/scripts/check-renderer.sh` проверяет реальный renderer внутри Fedora.

### Экспериментальный путь

```text
Fedora Mesa Zink / EGL
  → Android Vulkan loader wrapper (если доступен)
  → Android Vulkan
  → Immortalis-G925
```

Он не включён автоматически. Совместимость Android bionic libraries с glibc
userspace, Zink и конкретным Mali/Immortalis driver должна быть подтверждена
на устройстве. Qualcomm Turnip/Freedreno не используются.

`llvmpipe`, `softpipe`, `lavapipe` означают software rendering. Даже если
`glxgears` показывает FPS, это не доказательство GPU acceleration GNOME.

## 5. Input

Текущий transport использует возможности Termux:X11: touchpad emulation,
simulated touchscreen, right-click/two-finger scroll и keyboard overlay.
Это позволяет получить базовый touch UX, но не обещает Wayland tablet protocol,
S Pen pressure/tilt/palm data.

Целевой следующий слой:

```text
Android MotionEvent
  → Android bridge/frontend
  → Wayland tablet-v2/input protocols
  → Mutter
  → GTK application
```

До реализации этого слоя S Pen должен иметь `UNTESTED`, а mouse emulation не
должна называться полноценной stylus integration.

## 6. Android bridge

Bridge разделён на:

```text
Android app/service (android/)
  → официальные Android APIs, runtime/special permissions
Linux client (integration/)
  → Termux:API / Android intents / shared storage
GNOME adapters (future)
  → UPower/PipeWire/portal-compatible providers
```

Linux client использует allowlisted commands и не открывает сетевой listener.
Когда Fedora-сессия активна, `scripts/start.sh` запускает
`integration/android-bridge-broker.sh` в обычном Termux UID. Клиент в PRoot
передаёт через private shared-tmp только `list-apps`, `launch-package` и
фиксированные `launch-intent`; запросы и ответы валидируются, не source-ятся и
ограничены по размеру. PID broker привязан к project-owned Termux:X11
transport, а `stop.sh` удаляет очередь, чтобы не было отложенного запуска.

`sync-apps` создаёт только Fedora user `.desktop` entries. Выбранное
Android-приложение запускается штатным Android resolver и рисуется
SurfaceFlinger поверх Termux:X11. Это foreground hand-off, не native window
embedding в Wayland: rootless PRoot не может встроить произвольную Android
Activity в Mutter. При недоступном broker/resolver каталог не очищается.
Прямой loopback listener и background policy manager намеренно не добавляются:
они расширили бы поверхность атаки и нарушили Android safety contract.

The Android controller APK in `android/` is intentionally split from the Linux
client. Its first-run GUI is mandatory before the ON action is enabled. The
activity is a user-selectable Home candidate, and its auto-resume preference is
off by default. Its boot receiver is an observer/no-op and never launches a
hidden session. It sends only fixed `linux-mode.sh`, diagnostics and recovery
requests to Termux; the in-process `AndroidBridgeService` is not exported.

The controller hides only the persistent status bar while it is visible and
keeps the bottom navigation/mandatory-gesture region available. Android owns
the volume panel, notification shade and navigation; Fedora cannot block these
protected SystemUI surfaces. The visible desktop is a separate Termux:X11
Activity, so its user-controlled `Fullscreen on device display` preference must
remain off when reliable bottom-swipe or Back/Home buttons are needed. Fedora
Shell never changes that preference.

The Linux Mode controller is deliberately not an Android memory governor. It
owns only Fedora/Termux project processes and Fedora-side environment choices.
The Android memory report is read-only: it samples `/proc`, optional
`dumpsys meminfo`, zRAM/swap counters, PSI and best-effort Fedora PSS. The
allowlist is reporting metadata, not a package-control list. No Android
setting, AppOps value, package state, process state, LMKD/zRAM setting, kernel
parameter or system service is changed, so there is no Android policy to
restore when Linux Mode is disabled.

An unexpected non-zero Fedora/Devkit exit gets one bounded, sequential restart
attempt after the first `start.sh` process has returned and cleaned its
project-owned transport. There is no retry loop and no second concurrent PRoot
session; if the retry fails, the state is `crashed` and the user gets explicit
recovery controls.

The report also separates reclaimable/cache counters from `MemAvailable`, keeps
Android framework totals distinct from process PSS, and reports GPU memory as
unknown when the Android driver does not expose a reliable unprivileged value.
`SurfaceFlinger` PSS is never treated as GPU VRAM. This is the boundary for
Android-side optimization: measure and explain pressure, then let Android's
own LMKD/cached-app freezer/zRAM policy decide what to reclaim.

Samsung `RAM Plus` has a separate boundary: it is an Android/OEM user setting,
not a Fedora control. The project does not try to infer its exact UI state from
zRAM, does not enable or resize it, and reports `android.ramPlus.setting` as
`not-readable` when an unprivileged Termux probe cannot access an OEM API. The
report may still include read-only zRAM sysfs counters and clearly labels them
as indirect. This preserves the requirement that Android and One UI are not
modified while still showing whether the shared kernel exposes a swap backend.

### Linux Mode state machine

```text
Android Mode
  → user completes GUI setup and optionally selects Fedora Shell as Home
  → Linux Mode ON
  → read-only before snapshot
  → Termux:X11 + Fedora/PRoot + Mutter Devkit + GNOME Wayland
  → read-only after snapshot
  → Linux Mode OFF / recovery
  → only project-owned processes stop
  → Android Mode remains unchanged; Home is selected by Android
```

The state file and no-change receipt are written atomically. An interrupted
session is reported as `crashed`/`needs-recovery`; recovery stops only recorded
Fedora/Termux resources and never starts a kill/restart loop. If Fedora Shell
is selected as Home, returning to One UI still requires the user to choose One
UI Home in Android's Home app settings.

### Реальные Android ограничения

* global brightness требует special `WRITE_SETTINGS`; window brightness не
  управляет surface Termux:X11;
* background activity/foreground-service launches ограничены Android;
* clipboard из background может быть ограничен системой;
* SAF — правильный способ дать пользователю доступ к Documents/Downloads;
* default Home app меняется пользователем через Android Settings, приложение
  не является privileged system launcher;
* `Surface.setFrameRate`/`preferredRefreshRate` — только scheduler hints. Они
  не доказывают фактический presentation rate GNOME.

## 7. Power и lifecycle

Android остаётся владельцем lock screen, suspend/resume, battery policy и
refresh mode. Fedora не создаёт второй security lock screen. `start.sh` не
использует wakelock без необходимости; Termux/Termux:X11 battery optimization
нужно настроить вручную на устройстве.

Для 12 GiB RAM `FEDORA_MEMORY_PROFILE=auto` выбирает `low`: отключаются idle
GNOME helpers (settings daemon, terminal, WirePlumber, pipewire-pulse, keyring и
Tracker indexing), но сохраняется минимальный PipeWire display transport,
который нужен Mutter Devkit для вывода экрана,
анимации выключены, nested monitor понижается до 1920×1200, а
`MALLOC_ARENA_MAX`/`MALLOC_TRIM_THRESHOLD_` ограничивают fragmentation и
удержание свободной heap-памяти в долгоживущих glibc-процессах. Это advisory
profile, а не cgroup memory limit;
Android по-прежнему управляет reclaim, zram и suspend. Опции можно включить
точечно переменными `FEDORA_AUDIO_MODE`, `FEDORA_SETTINGS_DAEMON` и
`FEDORA_LAUNCH_TERMINAL`.

Явный профиль `maximum-linux` дополнительно выбирает Fedora-side nested
monitor 1600×1000, `MALLOC_ARENA_MAX=1` и более ранний allocator trim. Это
только компромисс между качеством/плавностью и памятью; Android-панель,
RAM Plus, zRAM, LMKD и kernel policy не меняются.

## 8. Backup/recovery

`proot-distro backup` архивирует rootfs и manifest; running process state не
сохраняется. `backup.sh` дополнительно сохраняет project state/config. Перед
update создаётся архив. `reset.sh` удаляет только Fedora container, а
`uninstall.sh` — только owned Termux shortcuts, boot hook, state и container.

## Источники

* [Fedora Linux 44 release](https://fedoramagazine.org/announcing-fedora-linux-44/)
* [Fedora Workstation 44 / GNOME 50](https://fedoramagazine.org/whats-new-fedora-workstation-44/)
* [PRoot-Distro](https://github.com/termux/proot-distro)
* [Termux:X11 README](https://github.com/termux/termux-x11/blob/master/README.md)
* [GNOME Mutter: building and running](https://github.com/GNOME/mutter/blob/main/doc/building-and-running.md)
* [GNOME 50 developer notes](https://release.gnome.org/50/developers/index.html)
* [Android memory management](https://developer.android.com/topic/performance/memory-management)
* [Android system-wide memory management](https://developer.android.com/topic/performance/memory/guide/system-wide-memory)
* [Android Surface.setFrameRate](https://developer.android.com/reference/android/view/Surface#setFrameRate(float,%20int,%20int))
* [Android background activity security](https://developer.android.com/guide/components/activities/secure-bal)
* [Android Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider)
* [Samsung RAM Plus](https://www.samsung.com/sg/support/mobile-devices/what-is-ram-plus-and-how-to-use-it/)
