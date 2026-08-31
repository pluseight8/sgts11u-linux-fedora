# Статус на 2026-08-31

Статус отражает код и исследование, а не результат на подключённом планшете.
Устройство в текущем окружении не подключено. Не меняйте `UNTESTED` на
`WORKING` без приложенного лога/команды проверки.

Допустимые значения: `WORKING`, `PARTIAL`, `ANDROID-BRIDGED`, `BROKEN`,
`UNSUPPORTED`, `UNTESTED`.

## Основные компоненты

| Component | Method | Status | Evidence / next test |
| --- | --- | --- | --- |
| Fedora ARM64 | official `fedora:44`, PRoot-Distro | PARTIAL | install path exists; run `uname -m`, `/etc/fedora-release` |
| GNOME Shell | Fedora package, nested session | UNTESTED | run `scripts/start.sh` |
| Mutter | nested Wayland compositor | UNTESTED | check `gnome-shell --help`, logs |
| GNOME apps | Fedora RPMs | UNTESTED | launch Nautilus/Settings/Console |
| D-Bus session | `dbus-run-session` | PARTIAL | process setup exists; inspect session bus |
| PipeWire | user process | UNTESTED | `pw-cli info 0`, audio test |
| WirePlumber | user process | UNTESTED | process/log check |
| xdg portals | user process | UNTESTED | portal smoke test |
| Display transport | Termux:X11 | PARTIAL | official PRoot shared-tmp path; device test pending |
| GNOME session | Wayland | UNTESTED | `XDG_SESSION_TYPE`, `WAYLAND_DISPLAY` |
| GTK apps | Wayland first | UNTESTED | `GDK_BACKEND`, app window protocol |
| Qt apps | Wayland first | UNTESTED | `QT_QPA_PLATFORM` and Qt app |
| XWayland | legacy compatibility | UNTESTED | launch X11-only app |
| GPU acceleration | virpipe / optional Zink | UNTESTED | renderer must not be llvmpipe |
| OpenGL | Mesa | UNTESTED | `glxinfo -B`, `eglinfo` |
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
| Fedora update | backup + `dnf upgrade` | PARTIAL | major release upgrade intentionally excluded |
| Backup/restore | PRoot archive + host state | PARTIAL | run restore verification on device |
| Reset/uninstall | scoped container/file removal | PARTIAL | script safety tests; device dry run pending |
| Android launcher APK | Home/emergency UI + Termux RUN_COMMAND | UNTESTED | build/install and permission test pending |
| Android bridge client | allowlisted Termux:API/intents | PARTIAL | shell/API paths exist; Android permission test pending |

## Wayland-specific status

| Component | Backend | Status |
| --- | --- | --- |
| GNOME Session | Wayland nested | UNTESTED |
| Mutter | Wayland compositor | UNTESTED |
| GTK apps | Wayland | UNTESTED |
| Qt apps | Wayland | UNTESTED |
| Firefox | Wayland | UNTESTED |
| Chromium | Wayland/Ozone | UNTESTED |
| Legacy X11 apps | XWayland | UNTESTED |
| Touch | Wayland input via transport | UNTESTED |
| S Pen | Wayland tablet/input | UNTESTED |
| Clipboard | Wayland ↔ Android | UNTESTED |
| GPU acceleration | Wayland/EGL/Vulkan | UNTESTED |
| 120 Hz presentation | Wayland frame pacing | UNTESTED |
| Android Home integration | user-selected Home + emergency controls | UNTESTED |

## Reference-only hardware facts

Samsung publishes 2960×1848, up to 120 Hz and model variants SM-X930/SM-X936;
MediaTek publishes Immortalis-G925 MC12 for Dimensity 9400+. These are not a
substitute for the tablet's `getprop`, display-mode and Vulkan outputs.
