# Fedora Shell Android component

This is a minimal Android launcher/emergency surface and an in-process bridge
API. It is deliberately dependency-light: no root, privileged permission,
custom ROM, SystemUI replacement or bootloader change is used.

## Build

Open `android/` in Android Studio or run it with a locally installed compatible
Gradle/Android SDK toolchain. The checked-in project uses the Android Gradle
Plugin 8.8.2, compile/target SDK 35 and min SDK 26. A Gradle wrapper is not
vendored, so the build host supplies Gradle and the SDK.

The app must be installed manually by the user. It does not download or install
Termux, Termux:X11, Termux:API or any Android app.

## Первоначальная GUI-настройка

1. Keep Termux, Termux:X11 and Termux:API on one signing source.
2. Grant Fedora Shell the additional `Run commands in Termux environment`
   permission.
3. Set `allow-external-apps=true` in Termux's `~/.termux/termux.properties`.
4. Run the repository installer once from Termux.
5. Open Fedora Shell and complete its first-run GUI wizard. The wizard only
   reads package availability, opens Termux:X11/diagnostics and records an
   app-local completion flag.
6. Optionally ask Android's own `ROLE_HOME` UI to offer Fedora Shell as Home.
   One UI Home remains installed and can be selected again at any time.

The app cannot modify Android settings, AppOps, package or process state,
SystemUI, LMKD, zRAM, kernel parameters or hardware services. It never
force-stops Android apps. Its memory screen first shows the Android
`ActivityManager` host snapshot and can then display the bounded Termux report
with Android attribution, Fedora/GNOME/Mutter PSS, zRAM/swap, PSI and
readability flags. These are read-only reports; the allowlist is reporting
metadata only, and unavailable values remain `unknown`/`null` rather than being
guessed.

The first-run GUI includes a RAM Plus guidance screen, but the action only opens
the public Android Settings page. RAM Plus is an OEM Android/storage-backed
virtual-memory option; the controller cannot enable it without modifying
Android. The report therefore separates indirect zRAM counters from the exact
Samsung switch and may show `android.ramPlus.setting=not-readable`.

The controller also has an Android deep-sleep guidance screen. It is deliberately
manual-only: Android/Samsung owns app standby, cached-process freezing, LMKD and
background restrictions, and this project never changes those policies, calls
`force-stop`, or writes AppOps. Put only genuinely nonessential apps into
Samsung's own deep-sleep list if you accept delayed notifications; keep
messengers, calls, VPN, navigation and hardware companions out unless you have
verified their behavior. The button opens Android Settings and performs no
Android mutation.

On Samsung firmware the button first tries Samsung's documented deep-sleep list
entry point (`com.samsung.android.sm.ACTION_OPEN_CHECKABLE_LISTACTIVITY`,
`activity_type=1`) and falls back to the public Android Settings screen when
the vendor activity is unavailable. Fedora Shell still cannot select an app on
the user's behalf.

The official Samsung guidance for the user-facing list is [Sleeping apps / Deep
sleeping apps](https://www.samsung.com/us/support/answer/ANS10003442/). Exact
labels may differ on the tablet's One UI build; apps that must deliver timely
messages, calls, navigation, VPN or accessory events should not be put there
without testing.

When the user taps `Linux Mode ON`, the launcher first opens the
foreground Termux:X11 activity. This is important on Android 12+ / One UI,
where a background `am start` from Termux can be rejected even though the X11
socket process is healthy. The optional Termux:Boot hook is a safe no-op
observer; it never starts a hidden Fedora/PRoot workload after boot. A
Termux:Widget launch is still best-effort and may require opening Termux:X11
manually.

The Android `BOOT_COMPLETED` receiver is intentionally an observer only. It
does not start Termux or Fedora while Android is still in the background; the
selected Home activity starts Linux Mode after it is visible. This avoids an
invisible Fedora process consuming RAM after boot and avoids relying on a
background activity launch that Android 12+ may reject.

When Fedora Shell is the selected Home app, it performs one small, read-only
`linux-mode.sh status` request through Termux's documented result callback. The
output is kept in memory only and is used to offer `Resume Linux Mode` or
`Restore Android Mode` after an unclean Fedora exit. This callback is not a
general shell channel and does not change Android state.

`Linux Focused` is the recommended profile for the tablet's approximately
12 GiB RAM. It reduces only Fedora-side helpers and nested compositor buffers.
`Balanced` and `Maximum Linux` also leave Android unchanged; the latter is an
explicit Fedora-only maximum with a smaller 1600×1000 nested buffer and stricter
allocator trimming.

If Fedora/Devkit exits unexpectedly, the controller performs at most one
sequential restart after the previous process and its owned transport have
finished cleaning up. A second failure is reported for explicit recovery; the
controller never creates a retry loop or a duplicate Fedora session.

The `Linux Mode OFF` action stops only project-owned Fedora/Termux resources.
If Fedora Shell was selected as Home, choose `One UI Home` in Android's
`Default apps → Home app` screen; the app cannot make that choice silently.

The controller hides only the persistent status bar while it is visible and
keeps the bottom navigation/mandatory-gesture region available. Android owns
the volume panel, notification shade and navigation; they cannot be blocked by
this ordinary app. The visible desktop is a separate Termux:X11 Activity, so
leave its `Fullscreen on device display` preference off when bottom-swipe or
Back/Home buttons are required. Fedora Shell does not change that preference.
The boot checkbox is off by default and is only best-effort on Samsung firmware.

### Клавиатура Linux Mode

При Linux Mode контроллер передаёт `FEDORA_KEYBOARD_MODE=linux` в Fedora
session. Это означает обычный focused-Activity путь через Termux:X11 →
Wayland/Mutter/GNOME. Пользователь должен тапнуть по поверхности Termux:X11
перед вводом сочетаний. В Android Mode никакого такого профиля нет.

Обычное Android-приложение не может глобально переназначить Home/Back,
громкость, уведомления, скриншоты, DeX и другие защищённые системные сочетания.
Они остаются у Android SystemUI. Fedora Shell не использует для этого
AccessibilityService, IME, overlay, root или изменение Android keymap. Для
проверки используйте `input/keyboard-mode.sh status --read-preferences`.
