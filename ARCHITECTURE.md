# Архитектура и решения

Дата среза исследования: **2026-08-31**.

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
4. Weston/other nested Wayland transport                    (fallback research)
5. Other Android Wayland frontend                           (candidate: tawc-like)
6. Termux:X11 transport → nested GNOME Wayland              (current transport)
7. XWayland for legacy applications                         (allowed)
8. Full X11 GNOME session                                   (explicit temporary fallback)
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
создаёт D-Bus session bus, запускает PipeWire/WirePlumber/portals best-effort
и затем GNOME Shell nested.

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
Это снижает поверхность атаки по сравнению с daemon на `0.0.0.0`. Прямой
loopback bridge с токеном может быть добавлен позже после отдельной модели
pairing/permission; в текущем прототипе Termux:API и RUN_COMMAND являются
каноническим non-root transport.

The optional Android APK in `android/` is intentionally split from the Linux
client. Its Home activity is user-selectable and its boot receiver is disabled
by default. It sends only fixed `start.sh`, `stop.sh` and `diagnostics.sh`
requests to Termux; the in-process `AndroidBridgeService` is not exported.

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
* [GNOME nested Shell testing](https://wiki.gnome.org/Initiatives%282f%29Wayland%282f%29GnomeShell%282f%29Testing.html)
* [Tess's Android Wayland Compositor research project](https://github.com/wmww/tawc)
* [Android Surface.setFrameRate](https://developer.android.com/reference/android/view/Surface#setFrameRate(float,%20int,%20int))
* [Android background activity security](https://developer.android.com/guide/components/activities/secure-bal)
* [Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)
