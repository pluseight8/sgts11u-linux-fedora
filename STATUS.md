# Статус на 2026-09-02

Статус отражает код и журналы владельца устройства на 2026-09-02. Полного
redacted diagnostics-файла нет, поэтому факты из консольного вывода отмечены
как наблюдённые, а аппаратные свойства, которых в нём нет, остаются
`UNTESTED`. Не меняйте `PARTIAL`/`UNTESTED` на `WORKING` без повторяемого
теста на самом планшете.

Допустимые значения: `WORKING`, `PARTIAL`, `ANDROID-BRIDGED`, `BROKEN`,
`UNSUPPORTED`, `UNTESTED`.

Подробный разбор причин чёрного экрана, границ Android-интеграции и
проверенных источников находится в [AUDIT.md](AUDIT.md). Эта рабочая копия ещё
не опубликована в Git remote и не установлена на планшет после последних
правок.

Последний аудит журнала показал не ошибку установки Fedora, а потерю
`mutter-devkit` после публикации nested Wayland-сокета. Supervisor теперь
проверяет живой viewer, сохраняет состояние PipeWire и runtime-сокетов в full
diagnostics и не объявляет чёрную/невидимую сессию успешной. Для гонки запуска
добавлен обратимый Fedora-only shim на точном пути
`/usr/libexec/mutter-devkit`: он ждёт официальное
`org.gnome.Mutter.Devkit` `Env`, затем запускает сохранённый RPM binary. Перед
`dnf` исходный binary восстанавливается, после пакетной операции shim
устанавливается заново. Неправильный standalone fallback удалён.
При отключённых portal проект не создаёт фальшивые D-Bus service-файлы для
portal; это убирает искусственные `ChildExited`/`AccessDenied` из старой схемы.
Визуальный результат на планшете всё ещё требует повторного acceptance-теста
после обновления control tree. Android contract зафиксирован: изменяются
только Fedora/Termux user-space и локальное состояние приложения; Android
policy, One UI и системные процессы не изменяются.

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
| Samsung keyboard | Linux Mode focused Termux:X11 → Wayland | PARTIAL | ordinary modifier matrix requires device test; Android global shortcuts remain SystemUI-owned |
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
| Android apps | local Termux broker + dynamic Fedora `.desktop` entries + explicit package launch | ANDROID-BRIDGED | launchable Android apps are enumerated read-only (all launchable packages by default; optional third-party-only scope) and shown above Fedora by Android SurfaceFlinger; native Wayland embedding and device acceptance remain untested |
| Notifications | optional Android bridge | UNTESTED | no listener enabled by default |
| Suspend/resume | Android-owned lifecycle | UNTESTED | screen off/wake/reconnect |
| Flatpak | namespaces/bwrap in PRoot | UNSUPPORTED | use RPM/AppImage unless tested |
| Fedora update | backup + `dnf upgrade` | PARTIAL | user log: package update completes; project-tree synchronization is now included |
| Memory profile | auto → low on ~12 GiB host | WORKING (policy) | low profile disables idle helpers, uses 1920×1200 nested mode, trims glibc arenas and records cache/PSI/swap plus RSS/PSS; explicit Maximum Linux uses 1600×1000; measure actual savings with `linux-mode.sh memory` |
| Linux Mode controller | Android app + Termux/PRoot state machine | PARTIAL | GUI wizard, three Fedora-side profiles, atomic recovery state and read-only Android receipt implemented; device acceptance pending |
| Home crash recovery | read-only `status` callback + recovery dialog | PARTIAL | Android GUI offers Resume/Restore after `crashed`/`exited`/`needs-recovery`; build and device acceptance pending |
| Backup/restore | PRoot archive + host state | PARTIAL | run restore verification on device |
| Reset/uninstall | scoped container/file removal | PARTIAL | script safety tests; device dry run pending |
| Android launcher APK | initial GUI + user-selected Home + Termux RUN_COMMAND | UNTESTED | build/install, wizard and Home-role acceptance test pending |
| Android bridge client | allowlisted read-only probes/intents + shared-tmp app broker | ANDROID-BRIDGED | broker lifecycle, bounded request protocol and fail-closed catalog are implemented; Android API 36 foreground-start acceptance test pending |

## Наблюдённый baseline устройства

| Fact | Value | Evidence |
| --- | --- | --- |
| Manufacturer/model | Samsung `SM-X930` | user-provided installer log |
| Android | 16 / API 36 | user-provided installer log |
| Host architecture | `aarch64` | user-provided installer log |
| RAM | 11788036 KiB (~12 GiB) | user-provided engineering probe |
| Free space at install | 319880192 KiB (later 318674260 KiB) | user-provided installer log |
| Fedora userspace | `fedora:44`, `aarch64` | user-provided PRoot-Distro log |
| GNOME/Mutter | 50.4 on Fedora 44 | user-provided Fedora package/log output |
| Termux:X11 package | `1.03.01-6` nightly | user-provided package output |
| GPU state observed | no hardware renderer; surfaceless/software fallback | user-provided `fedora-session.log` |

This baseline does not include `ro.soc.model`, panel mode, Vulkan device,
SELinux state or a redacted full report. Collect them with:

```bash
bash ./scripts/diagnostics.sh --full --redact --frame-pacing
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
