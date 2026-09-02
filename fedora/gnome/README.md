# GNOME session

`fedora-session` is a small supervisor for a Fedora userspace running without
GDM/systemd. It creates a D-Bus session bus, starts an isolated minimal
PipeWire transport required by the Mutter Devkit viewer, and tries
`gnome-shell --wayland --devkit` first. WirePlumber and pipewire-pulse are
optional audio helpers. Desktop portals and Evolution/GOA calendar helpers are
disabled by default in the low-memory profile; portals are enabled only when
Android/PRoot can open `/dev/fuse`. When portals are disabled, GTK/GIO client
guards are used and the private bus does not install fake portal services:
Mutter's optional portal probes should see the normal `ServiceUnknown` result,
not a synthetic `/usr/bin/false` activation or a broad D-Bus denial.

On GNOME 49 and later, the Development Kit replaces the old `--nested` option.
The outer Android display transport is Termux:X11, while the desktop session
inside the viewer window is Wayland. On older GNOME versions the supervisor
falls back to `gnome-shell --nested --wayland`. Because the outer transport is
Termux:X11, the Devkit GTK viewer is forced to the X11 backend by default. The
direct GNOME Shell process remains explicitly Wayland-only; the private D-Bus
activation environment is used for helper processes and compatibility probes.
This separation prevents GNOME Shell from trying to initialize its unsupported
X11 services while the viewer still gets a visible outer surface.

GNOME's official Devkit path starts `/usr/libexec/mutter-devkit` directly from
the compositor; the viewer then reads its nested `WAYLAND_DISPLAY` from the
compositor-owned `org.gnome.Mutter.Devkit` `Env` property. Slow PRoot startup
can otherwise make the viewer run before that property exists. The Fedora
integration therefore installs a reversible Fedora-only shim at that exact
path. The shim waits a bounded interval for the official D-Bus object/property
and then executes the saved RPM binary at
`/usr/local/libexec/fedora-shell/mutter-devkit.real`. The original binary is
restored before every Fedora RPM transaction and the shim is reapplied after
the transaction. If the object or the trusted original is unavailable, startup
fails closed; there is no invalid standalone viewer fallback. The actual
Wayland socket and renderer must be recorded by diagnostics. Low memory mode
also disables inner Xwayland while keeping the outer Termux:X11 viewer, so
legacy X11 applications are intentionally not available until
`FEDORA_NESTED_XWAYLAND=on` is selected.

Before starting GNOME, the Termux-side launcher checks the Fedora guest as
guest root and, only when PRoot has no real systemd PID 1, temporarily renames
the stale guest-only `/run/systemd/seats` marker to an adjacent backup. The
backup is restored on cleanup. Fedora-local dconf values used by the low-memory
compatibility profile are also restored on normal exit and recovered after an
abrupt stop. Android `/run`, Android settings and Android services are never
touched by this compatibility step.

While the host `start.sh` is alive, it also supervises a local Android app
broker. The session calls `fedora-android-bridge sync-apps`, which creates only
user-owned Fedora desktop entries for launchable Android packages discovered by
the read-only resolver. The default scope is `all`, so preinstalled/system
applications with a launcher activity may also appear; set
`FEDORA_ANDROID_APPS_SCOPE=user` to restrict the catalog to packages identified
as third-party by the read-only package inventory. This is an enumeration scope,
not a permission or memory-policy allowlist.
The source client stays in the `/opt/fedora-shell` bind mount; guest
integration installs a Fedora-native wrapper because the source deliberately
uses the Termux interpreter path.
Launching one is an explicit Android foreground hand-off above the X11
transport; it is not Activity embedding and does not require package, AppOps,
LMKD, zRAM or Android settings changes. A failed broker refresh leaves the
previous catalog untouched.
