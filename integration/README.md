# Android bridge and app entries

`android-bridge.sh` is intentionally a narrow, non-networked client. It uses
Termux:API for operations that Android already exposes and Android `am`
intents for settings/app launch. It never opens a TCP listener and it does not
accept an arbitrary package name or shell command.

The script is bind-mounted into Fedora at `/opt/fedora-shell` and copied to
`/usr/local/bin/fedora-android-bridge`. `fedora/gnome/install-integration.sh`
creates desktop entries from `android-apps.conf` for the allowlisted package
IDs. Package IDs are regional/installation-dependent; a missing app fails at
launch time instead of being installed silently.

Required user setup:

1. Install Termux:API from the same signing source as Termux.
2. Grant only the runtime permissions needed for battery, clipboard, camera,
   microphone or vibration tests.
3. Set `allow-external-apps=true` in `~/.termux/termux.properties` only when
   using the Fedora Shell Android app / external RUN_COMMAND integration.
4. Reopen Termux after changing that property.

Brightness, background clipboard, foreground activity launches and some sensor
operations remain Android-policy dependent. They are not represented as fake
Linux kernel devices.
