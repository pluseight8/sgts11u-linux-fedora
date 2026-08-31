# GNOME session

`fedora-session` is a small supervisor for a Fedora userspace running without
GDM/systemd. It creates a D-Bus session bus, starts the minimal PipeWire
transport required by the Mutter Devkit viewer, and tries
`gnome-shell --wayland --devkit` first. WirePlumber and pipewire-pulse are
optional audio helpers. Desktop portals are enabled only when Android/PRoot can
open `/dev/fuse`.

On GNOME 49 and later, the Development Kit replaces the old `--nested` option.
The outer Android display transport is Termux:X11, while the desktop session
inside the viewer window is Wayland. On older GNOME versions the supervisor
falls back to `gnome-shell --nested --wayland`. Because the outer transport is
Termux:X11, the Devkit GTK viewer is forced to the X11 backend by default; the
supervisor verifies that the viewer process remains alive before reporting a
ready desktop. The actual Wayland socket and renderer must be recorded by
diagnostics.
