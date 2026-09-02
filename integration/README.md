# Android bridge and app entries

`android-bridge.sh` is intentionally a narrow, non-networked client. It uses
Termux:API for operations that Android already exposes and Android `am`
intents for settings/app launch. It never opens a TCP listener and it does not
accept an arbitrary shell/RPC command or an unsanitized intent payload. An
explicitly selected Android package may be passed only after strict package
name validation.

The source bridge is bind-mounted into Fedora at `/opt/fedora-shell`. Because
it intentionally uses the Termux interpreter path, the guest installs a
Fedora-native wrapper at `/usr/local/bin/fedora-android-bridge`; the wrapper
executes the bind-mounted source with Fedora's `/bin/bash`.
`fedora/gnome/install-integration.sh` creates desktop entries from
`android-apps.conf` for the allowlisted IDs.
Entries use stable Android intent actions by default. A user may explicitly add
an exact `package:org.example.app` target for an installed app; firmware-
dependent Samsung/Google package maps are not built into the project, and a
missing target fails at launch time instead of being installed silently.

## Android applications in Fedora

When `start.sh` is running, it starts `android-bridge-broker.sh` in the
ordinary Termux UID. The broker is a private file queue under
`$PREFIX/tmp/fedora-runtime/android-bridge`; it supports only:

* read-only enumeration of launchable Android packages with a launcher
  activity (all visible packages by default; third-party-only is optional);
* one exact, user-selected package launch; and
* the fixed Android settings intents already present in this client.

At Fedora session startup, `sync-apps` creates user desktop files named
`fedora-android-user-*.desktop`. By default the read-only resolver uses
`FEDORA_ANDROID_APPS_SCOPE=all`, so launchable preinstalled Samsung/Google/
system applications are included as well as ordinary user applications. This
is only a catalog scope; it is never a package allowlist for stopping or
restricting anything. To keep a third-party-only catalog, set
`FEDORA_ANDROID_APPS_SCOPE=user` in the Fedora Shell config. The same action is
available from the GNOME entry **Refresh Android applications** or directly:

```bash
fedora-android-bridge list-apps       # user-installed applications
fedora-android-bridge list-apps --all # all launchable applications
fedora-android-bridge sync-apps
```

Clicking one of these entries asks Android to start its own application. The
Android application is therefore rendered by Android/SurfaceFlinger above the
Termux:X11/Fedora surface. This is a reliable foreground hand-off; it is not
native embedding of an Android Activity inside a Wayland compositor. Back/Home
returns to the foreground Android activity selected by the system (normally
Termux:X11 or Fedora Shell if it is the selected Home app). Android 12+ may
reject a background activity start; keep the Termux:X11 companion Activity
visible and retry from the Fedora desktop.

If the broker or Android package resolver is unavailable, `sync-apps` fails
closed and retains the previous dynamic entries. It never installs, disables,
suspends, force-stops, clears or otherwise changes an Android package. Set
`FEDORA_ANDROID_APPS_MODE=off` to disable automatic refresh while retaining
existing entries; `on`/`auto` enables it for the next session. The `all` scope
prefers Android's read-only `query-activities` resolver when package inventory
access is restricted; it never falls back to a broad shell command or an
unvalidated package name.

Required user setup:

1. Install Termux:API from the same signing source as Termux.
2. Grant only the runtime permissions needed for read-only battery/capability
   probes or a user-triggered camera/microphone operation.
3. Set `allow-external-apps=true` in `~/.termux/termux.properties` only when
   using the Fedora Shell Android app / external RUN_COMMAND integration.
4. Reopen Termux after changing that property.

`android-memory-governor.sh` is intentionally read-only: it reports shared host
RAM, zRAM/swap counters, PSI, RAM Plus indirect evidence and best-effort Fedora
PSS. It does not change Android settings, AppOps, package/process state, LMKD,
zRAM or kernel values. Samsung RAM Plus is reported as `not-readable` unless a
future permitted Android API exposes it; seeing zRAM is not treated as proof
that the OEM switch is enabled.
Brightness, background clipboard, foreground activity launches and some sensor
operations remain Android-policy dependent. They are not represented as fake
Linux kernel devices, and no hidden Android setter is provided.
