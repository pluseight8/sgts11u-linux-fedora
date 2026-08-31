# GNOME session

`fedora-session` is a small supervisor for a Fedora userspace running without
GDM/systemd. It creates a D-Bus session bus, starts user-level audio/portal
processes when present, and tries `gnome-shell --nested --wayland` first.

The nested GNOME command is a compatibility path: the outer Android display
transport is Termux:X11, while the desktop session inside the window is
Wayland. The actual Wayland socket and renderer must be recorded by diagnostics.

