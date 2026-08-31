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

## Setup after install

1. Keep Termux, Termux:X11 and Termux:API on one signing source.
2. Grant Fedora Shell the additional `Run commands in Termux environment`
   permission.
3. Set `allow-external-apps=true` in Termux's `~/.termux/termux.properties`.
4. Run the repository installer once from Termux.
5. Optionally choose Fedora Shell as Home in Android Settings. One UI Home
   remains installed and can be selected again at any time.

The Home activity hides system bars while it is visible, but it cannot remove
SystemUI or override Android lock-screen/background policy. The boot checkbox is
off by default and is only best-effort on Samsung firmware.
