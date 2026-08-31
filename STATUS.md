# Статус на 2026-08-31

Статус отражает код и журналы владельца устройства на 2026-08-31. Полного
redacted diagnostics-файла нет, поэтому факты из консольного вывода отмечены
как наблюдённые, а аппаратные свойства, которых в нём нет, остаются
`UNTESTED`. Не меняйте `PARTIAL`/`UNTESTED` на `WORKING` без повторяемого
теста на самом планшете.

Допустимые значения: `WORKING`, `PARTIAL`, `ANDROID-BRIDGED`, `BROKEN`,
`UNSUPPORTED`, `UNTESTED`.

## Основные компоненты

| Component | Method | Status | Evidence / next test |
| --- | --- | --- | --- |
| Fedora ARM64 | official `fedora:44`, PRoot-Distro | WORKING | user log: image installed and Fedora package transaction completed; rerun `diagnostics.sh --fedora` after updates |
| GNOME Shell | Fedora package, nested session | PARTIAL | user log: `gnome-shell --wayland --devkit` publishes `wayland-0`, but visible output is black; no successful visual acceptance yet |
| Mutter | nested Wayland compositor | PARTIAL | user log: Mutter Devkit starts, creates Wayland socket and surfaceless renderer; verify visible frame |
| GNOME apps | Fedora RPMs | PARTIAL | user log: Ptyxis starts; desktop surface remains black |
| D-Bus session | `dbus-run-session` | PARTIAL | process setup exists; inspect session bus |
| PipeWire | user process | UNTESTED | `pw-cli info 0`, audio test |
| WirePlumber | user process | UNTESTED | process/log check |
| xdg portals | user process | PARTIAL | `/dev/fuse` denied under Android; use `FEDORA_PORTAL_MODE=off`, then test file chooser separately |
| Display transport | Termux:X11 | PARTIAL | user log: stale process once had no X0 socket; next run published desktop; visible frame still black |
| GNOME session | Wayland | PARTIAL | user log: `Desktop session: Wayland (wayland-0) ... transport: X11 (:0)` |
| GTK apps | Wayland first | PARTIAL | Ptyxis activation observed; verify a normal GTK window after legacy drawing fix |
| Qt apps | Wayland first | UNTESTED | `QT_QPA_PLATFORM` and Qt app |
| XWayland | legacy compatibility | UNTESTED | launch X11-only app |
| GPU acceleration | virpipe / optional Zink | PARTIAL | user log: `Created surfaceless renderer without GPU` and Xwayland software fallback; hardware acceleration is not proven |
| OpenGL | Mesa | PARTIAL | software path observed; run `glxinfo -B`/`eglinfo` for exact renderer |
| Vulkan | Android wrapper / native probe | UNTESTED | `vulkaninfo --summary` |
| Firefox | Wayland | UNTESTED | `about:support` → Window Protocol |
| Chromium/Electron | Ozone Wayland | UNTESTED | inspect actual backend |
| 120 Hz presentation | Android scheduler + nested output | UNTESTED | frame pacing report, not display mode only |
| Touch | Termux:X11 gestures | PARTIAL | transport supports emulation; device test pending |
| Multitouch | X11 transport gestures | UNTESTED | pinch/scroll/overview test |
| S Pen position | Android → input | UNTESTED | pointer coordinate test |
| S Pen pressure | Wayland tablet protocol | UNTESTED | Xournal++ pressure test |
| S Pen hover/tilt | Android MotionEvent bridge | UNTESTED | Android event capture |
| Samsung keyboard | Android/Termux input | UNTESTED | modifier/media key matrix |
| Touchpad | Android/Termux input | UNTESTED | click/scroll/gesture matrix |
| Audio output | Android/Termux Pulse transport | UNTESTED | speaker/Bluetooth/USB |
| Microphone | Termux:API/Android audio | UNTESTED | PipeWire/Pulse capture |
| Wi-Fi | Android network | ANDROID-BRIDGED | no fake Linux wlan device |
| Bluetooth | Android stack | ANDROID-BRIDGED | UI bridge pending |
| Internet | Android network inherited | UNTESTED | Fedora DNS/HTTPS |
| Battery | Termux:API/Android BatteryManager | ANDROID-BRIDGED | permission/device test |
| Brightness | Android `WRITE_SETTINGS`/Termux API | UNTESTED | special permission + slider |
| Volume | Android AudioManager/Termux API | UNTESTED | media volume test |
| Rotation | Android sensor | UNTESTED | orientation service + Mutter output |
| Clipboard | Termux API ↔ Wayland | UNTESTED | text/URL/image test |
| Shared files | SAF / shared storage bind | PARTIAL | bind only when user grants storage |
| Camera | Android app/bridge | ANDROID-BRIDGED | launcher path only |
| Android apps | explicit package intents | PARTIAL | allowlisted desktop entries; package IDs user supplied |
| Notifications | optional Android bridge | UNTESTED | no listener enabled by default |
| Suspend/resume | Android-owned lifecycle | UNTESTED | screen off/wake/reconnect |
| Flatpak | namespaces/bwrap in PRoot | UNSUPPORTED | use RPM/AppImage unless tested |
| Fedora update | backup + `dnf upgrade` | PARTIAL | user log: package update completes; project-tree synchronization is now included |
| Memory profile | auto → low on ~12 GiB host | WORKING (policy) | low profile disables idle helpers, uses 2560×1600 nested mode, trims glibc arenas and records RSS/PSS; measure actual savings with `diagnostics.sh --full --redact` |
| Backup/restore | PRoot archive + host state | PARTIAL | run restore verification on device |
| Reset/uninstall | scoped container/file removal | PARTIAL | script safety tests; device dry run pending |
| Android launcher APK | Home/emergency UI + Termux RUN_COMMAND | UNTESTED | build/install and permission test pending |
| Android bridge client | allowlisted Termux:API/intents | PARTIAL | shell/API paths exist; Android permission test pending |

## Наблюдённый baseline устройства

| Fact | Value | Evidence |
| --- | --- | --- |
| Manufacturer/model | Samsung `SM-X930` | user-provided installer log |
| Android | 16 / API 36 | user-provided installer log |
| Host architecture | `aarch64` | user-provided installer log |
| Free space at install | 319880192 KiB (later 318674260 KiB) | user-provided installer log |
| Fedora userspace | `fedora:44`, `aarch64` | user-provided PRoot-Distro log |
| GNOME/Mutter | 50.4 on Fedora 44 | user-provided Fedora package/log output |
| Termux:X11 package | `1.03.01-6` nightly | user-provided package output |
| GPU state observed | no hardware renderer; surfaceless/software fallback | user-provided `fedora-session.log` |

This baseline does not include `ro.soc.model`, panel mode, Vulkan device,
RAM, SELinux state or a redacted full report. Collect them with:

```bash
./scripts/diagnostics.sh --full --redact --frame-pacing
```

## Wayland-specific status

| Component | Backend | Status |
| --- | --- | --- |
| GNOME Session | Wayland nested | PARTIAL |
| Mutter | Wayland compositor | PARTIAL |
| GTK apps | Wayland | PARTIAL |
| Qt apps | Wayland | UNTESTED |
| Firefox | Wayland | UNTESTED |
| Chromium | Wayland/Ozone | UNTESTED |
| Legacy X11 apps | XWayland | UNTESTED |
| Touch | Wayland input via transport | UNTESTED |
| S Pen | Wayland tablet/input | UNTESTED |
| Clipboard | Wayland ↔ Android | UNTESTED |
| GPU acceleration | Wayland/EGL/Vulkan | PARTIAL |
| 120 Hz presentation | Wayland frame pacing | UNTESTED |
| Android Home integration | user-selected Home + emergency controls | UNTESTED |

## Reference-only hardware facts

Samsung publishes 2960×1848, up to 120 Hz and model variants SM-X930/SM-X936;
MediaTek publishes Immortalis-G925 MC12 for Dimensity 9400+. These are not a
substitute for the tablet's `getprop`, display-mode and Vulkan outputs.
