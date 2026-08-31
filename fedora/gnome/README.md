# GNOME session

`fedora-session` is a small supervisor for a Fedora userspace running without
GDM/systemd. It creates a D-Bus session bus, starts user-level audio/portal
processes when present, and tries `gnome-shell --wayland --devkit` first.

On GNOME 49 and later, the Development Kit replaces the old `--nested` option.
The outer Android display transport is Termux:X11, while the desktop session
inside the viewer window is Wayland. On older GNOME versions the supervisor
falls back to `gnome-shell --nested --wayland`. The actual Wayland socket and
renderer must be recorded by diagnostics.
