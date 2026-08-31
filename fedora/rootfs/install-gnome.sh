#!/usr/bin/env bash
set -Eeuo pipefail

# Runs inside the Fedora PRoot guest as root. It installs a userland only;
# Android's init, kernel, SELinux and hardware partitions remain untouched.

FEDORA_RELEASE="${FEDORA_RELEASE:-44}"
FEDORA_USER="${FEDORA_USER:-fedora}"

if [[ "$(id -u)" != 0 ]]; then
  printf '%s\n' 'This setup script must be invoked as the PRoot guest root.' >&2
  exit 1
fi

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# A single Fedora mirror can time out while the remaining repositories are
# usable. Keep the warning visible, but let the refresh/transaction below
# make the final decision about whether the package operation can proceed.
if ! dnf -y makecache; then
  printf '%s\n' 'Warning: Fedora metadata refresh was incomplete; retrying during package upgrade.' >&2
fi
dnf -y upgrade --refresh --setopt=install_weak_deps=False

required_packages=(
  bash
  ca-certificates
  dbus-daemon
  dbus-tools
  dconf
  fontconfig
  gnome-control-center
  gnome-keyring
  gnome-session
  gnome-settings-daemon
  gnome-shell
  gsettings-desktop-schemas
  libinput
  mesa-demos
  mesa-dri-drivers
  mesa-libEGL
  mesa-libGL
  mutter
  mutter-devkit
  nautilus
  pipewire
  pipewire-pulseaudio
  pipewire-utils
  wireplumber
  xdg-desktop-portal
  xdg-desktop-portal-gtk
  xorg-x11-server-Xwayland
  xorg-x11-xauth
  xkeyboard-config
  vulkan-tools
  wayland-utils
)

dnf -y install --setopt=install_weak_deps=False "${required_packages[@]}"

# Fedora package names have changed across GNOME releases. Install the first
# available terminal and the optional GNOME utilities independently so a name
# change does not discard the complete desktop install.
optional_packages=(
  ptyxis
  gnome-console
  gnome-terminal
  gnome-text-editor
  gnome-calculator
  gnome-system-monitor
  glmark2
  wmctrl
)
for package in "${optional_packages[@]}"; do
  if dnf -q list --available "$package" >/dev/null 2>&1; then
    dnf -y install --setopt=install_weak_deps=False "$package" || true
  fi
done

install -d -m 0755 /etc/fedora-shell /usr/local/bin

if ! id "$FEDORA_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$FEDORA_USER"
fi

user_home="$(getent passwd "$FEDORA_USER" | awk -F: '{print $6}')"
if [[ -z "$user_home" ]]; then
  printf 'Could not resolve home for %s\n' "$FEDORA_USER" >&2
  exit 1
fi
install -d -m 0700 -o "$FEDORA_USER" -g "$FEDORA_USER" "$user_home/.config/fedora-shell"

cat > /etc/fedora-shell/release <<EOF
FEDORA_RELEASE=$FEDORA_RELEASE
FEDORA_USER=$FEDORA_USER
ROOTFS_POLICY=official-oci-via-proot-distro
SYSTEMD_PID1=not-used
ANDROID_KERNEL=host
EOF
chmod 0644 /etc/fedora-shell/release

# PRoot cannot provide systemd PID 1. Keep this marker explicit so users do not
# mistake a failed service enablement for a missing Android component.
install -d -m 0755 /etc/systemd/system
cat > /etc/fedora-shell/README <<'EOF'
This Fedora userspace runs under Android + PRoot-Distro.
systemd is not PID 1 here. Do not use systemctl as a health check.
fedora-session starts a private D-Bus session bus, a minimal PipeWire display
transport and GNOME; WirePlumber/pipewire-pulse are optional helpers enabled by
the audio profile. The private bus is also exposed as a compatibility
system-bus address
because PRoot cannot provide Android/systemd's system bus. This does not
provide logind, UPower, RTKit or other privileged system services. Desktop
portals are enabled only when their Android/PRoot FUSE prerequisite is usable.
EOF
chmod 0644 /etc/fedora-shell/README

dnf -y clean all
printf '%s\n' "Fedora ${FEDORA_RELEASE} GNOME package setup complete for ${FEDORA_USER}."
