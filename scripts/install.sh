#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-installer-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/guest-config.sh"

FEDORA_ASSUME_YES="${FEDORA_ASSUME_YES:-0}"
ALLOW_UNKNOWN_DEVICE=0
SKIP_X11_PACKAGE=0
INSTALL_EXPERIMENTAL_GPU=0
MIN_FREE_GIB=12

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/install.sh [OPTIONS]

Options:
  --yes                    accept installer confirmations
  --allow-unknown-device  continue when the Android model is not recognised
  --enable-boot            install the safe, non-launching Termux:Boot observer
  --skip-x11-package       do not install termux-x11-nightly from x11-repo
  --experimental-gpu       install optional virgl bridge; never enables it automatically
  --memory-profile NAME    auto, low, balanced or performance (default: auto)
  --min-free-gib N         require N GiB of free space (default: 12)
  -h, --help               show this help
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --yes)
      FEDORA_ASSUME_YES=1
      shift
      ;;
    --allow-unknown-device)
      ALLOW_UNKNOWN_DEVICE=1
      shift
      ;;
    --enable-boot)
      ENABLE_BOOT=1
      shift
      ;;
    --skip-x11-package)
      SKIP_X11_PACKAGE=1
      shift
      ;;
    --experimental-gpu)
      INSTALL_EXPERIMENTAL_GPU=1
      shift
      ;;
    --memory-profile)
      (( $# >= 2 )) || { usage; exit 64; }
      FEDORA_MEMORY_PROFILE="$2"
      shift 2
      ;;
    --min-free-gib)
      (( $# >= 2 )) || { usage; exit 64; }
      MIN_FREE_GIB="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fedora_die "Unknown option: $1"
      exit 64
      ;;
  esac
done

ENABLE_BOOT="${ENABLE_BOOT:-0}"

[[ "$MIN_FREE_GIB" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  fedora_die "--min-free-gib must be a positive number"
  exit 64
}
awk -v gib="$MIN_FREE_GIB" 'BEGIN { exit !(gib > 0) }' || {
  fedora_die "--min-free-gib must be greater than zero"
  exit 64
}
FEDORA_MEMORY_PROFILE="$(fedora_resolve_memory_profile "$FEDORA_MEMORY_PROFILE")" || {
  fedora_die "--memory-profile must be auto, low, balanced or performance"
  exit 64
}

fedora_init_log
fedora_require_termux
fedora_require_non_root
for required_command in pkg uname df awk mkdir cp chmod date mktemp; do
  fedora_require_cmd "$required_command"
done

host_arch="$(uname -m)"
case "$host_arch" in
  aarch64|arm64) ;;
  *)
    fedora_die "ARM64 host required; uname -m returned: $host_arch"
    exit 1
    ;;
esac

device_model="$(fedora_getprop ro.product.model)"
device_manufacturer="$(fedora_getprop ro.product.manufacturer)"
device_codename="$(fedora_getprop ro.product.device)"
device_board="$(fedora_getprop ro.board.platform)"
device_hardware="$(fedora_getprop ro.hardware)"
device_soc="$(fedora_getprop ro.soc.model)"
android_release="$(fedora_getprop ro.build.version.release)"
android_api="$(fedora_getprop ro.build.version.sdk)"
android_security_patch="$(fedora_getprop ro.build.version.security_patch)"
kernel_release="$(uname -r 2>/dev/null || true)"
selinux_state="unknown"
if fedora_have_cmd getenforce; then
  selinux_state="$(getenforce 2>/dev/null || true)"
elif [[ -r /sys/fs/selinux/enforce ]]; then
  selinux_state="$(< /sys/fs/selinux/enforce)"
fi
ram_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)"
device_ok=0
case "$device_model" in
  SM-X930|SM-X936) device_ok=1 ;;
esac
if (( ! device_ok && ! ALLOW_UNKNOWN_DEVICE )); then
  fedora_die "Unrecognised model '$device_model'. Use --allow-unknown-device only for research on a compatible ARM64 device."
  exit 1
fi

free_kib="$(fedora_free_kib "$FEDORA_USER_HOME")"
min_free_kib="$(awk -v gib="$MIN_FREE_GIB" 'BEGIN { printf "%.0f", gib * 1024 * 1024 }')"
if [[ ! "$free_kib" =~ ^[0-9]+$ ]]; then
  fedora_die "Unable to determine free space for $FEDORA_USER_HOME; refusing to install without a safety check."
  exit 1
fi
if (( free_kib < min_free_kib )); then
  fedora_die "At least ${MIN_FREE_GIB} GiB is required; only $((free_kib / 1024 / 1024)) GiB is free."
  exit 1
fi

fedora_log "Device: ${device_manufacturer:-unknown} ${device_model:-unknown}; Android ${android_release:-unknown} (API ${android_api:-unknown}); host ${host_arch}."
fedora_log "Engineering probe: codename=${device_codename:-unknown}; board=${device_board:-unknown}; SoC=${device_soc:-unknown}; hardware=${device_hardware:-unknown}; kernel=${kernel_release:-unknown}; SELinux=${selinux_state:-unknown}; RAM=${ram_kib:-unknown} KiB."
fedora_log "Memory profile: ${FEDORA_MEMORY_PROFILE} (use FEDORA_MEMORY_PROFILE=balanced for full GNOME helpers)."
fedora_log "Free space check: ${free_kib:-unknown} KiB available; ${MIN_FREE_GIB} GiB requested."

fedora_init_state
if ! fedora_atomic_write "$FEDORA_STATE_DIR/install-device-probe.env" 600 <<EOF
timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
manufacturer=$(printf '%q' "$device_manufacturer")
model=$(printf '%q' "$device_model")
codename=$(printf '%q' "$device_codename")
board=$(printf '%q' "$device_board")
hardware=$(printf '%q' "$device_hardware")
soc=$(printf '%q' "$device_soc")
android_release=$(printf '%q' "$android_release")
android_api=$(printf '%q' "$android_api")
android_security_patch=$(printf '%q' "$android_security_patch")
host_arch=$(printf '%q' "$host_arch")
kernel_release=$(printf '%q' "$kernel_release")
selinux=$(printf '%q' "$selinux_state")
ram_kib=$(printf '%q' "${ram_kib:-unknown}")
memory_profile=$(printf '%q' "$FEDORA_MEMORY_PROFILE")
free_kib=$(printf '%q' "${free_kib:-unknown}")
EOF
then
  fedora_die "Could not record the device probe safely"
  exit 1
fi

if ! fedora_confirm "Install/update Termux packages and the Fedora container now?"; then
  fedora_die "Installation cancelled."
  exit 1
fi

fedora_log "Updating Termux packages as one complete rolling-release transaction."
pkg update -y
fedora_termux_full_upgrade
pkg install -y proot-distro termux-api
if (( ! SKIP_X11_PACKAGE )); then
  pkg install -y x11-repo
  pkg install -y termux-x11-nightly
else
  fedora_warn "Skipping termux-x11-nightly; start.sh will require a manually installed compatible X11 package."
fi
if [[ -x /system/bin/pm || -x /system/bin/cmd ]]; then
  if fedora_android_package_installed com.termux.x11; then
    fedora_log "Read-only check confirms the compatible Termux:X11 Android APK is installed."
  else
    package_check_rc=$?
    fedora_warn "Could not confirm com.termux.x11 through the read-only Android package API (rc=$package_check_rc); install/open the compatible APK from the same source as Termux before starting GNOME."
  fi
fi
if (( INSTALL_EXPERIMENTAL_GPU )); then
  if pkg list-all 2>/dev/null | grep -Eq '(^|[[:space:]])virglrenderer-android/'; then
    fedora_log "Installing optional virglrenderer-android bridge (experimental; not enabled by auto mode)."
    pkg install -y virglrenderer-android
  else
    fedora_warn "virglrenderer-android is not available in the configured Termux repositories; continuing without it."
  fi
fi

fedora_require_pd
install_root="$(fedora_install_root)"
install_marker="$install_root/.fedora-shell-install"
fedora_path_is_safe "$install_root" || {
  fedora_die "Refusing an unsafe installation path: $install_root"
  exit 1
}
fedora_install_root_path_is_safe "$install_root" || {
  fedora_die "Installation root must be a safe child of the Termux home and outside the checkout: $install_root"
  exit 1
}
if [[ -L "$install_root" || ( -e "$install_root" && ! -d "$install_root" ) ]]; then
  fedora_die "Refusing an unsafe installation directory: $install_root"
  exit 1
fi
if [[ -e "$install_root" && ! -f "$install_marker" ]]; then
  fedora_die "Refusing to use existing non-project directory: $install_root"
  exit 1
fi
fedora_prepare_directories "$install_root" || {
  fedora_die "Could not prepare the installation directory safely: $install_root"
  exit 1
}
if [[ ! -f "$install_marker" ]]; then
  if ! fedora_atomic_write "$install_marker" 600 <<EOF
# fedora-shell-install-marker-v1
installed_by=$(printf '%q' "$FEDORA_PROJECT_ROOT/scripts/install.sh")
EOF
  then
    fedora_die "Could not create the installation marker safely"
    exit 1
  fi
fi

# Keep an installed copy so the one-tap shortcut remains usable after the
# checkout is moved or deleted. Existing project-owned files are updated;
# unrelated files in the installation directory are never removed. If the
# command was launched from the installed copy, use the real checkout when it
# is available so a future update can still refresh this control tree.
source_project_root="$FEDORA_PROJECT_ROOT"
if [[ ! -d "$source_project_root/.git" && -d "$FEDORA_CHECKOUT_ROOT/.git" ]]; then
  source_project_root="$FEDORA_CHECKOUT_ROOT"
fi
FEDORA_CHECKOUT_ROOT="$source_project_root"
fedora_repair_project_modes "$source_project_root"
fedora_sync_project_tree "$source_project_root" "$install_root"

write_config() {
  umask 077
  local config_dir config_tmp
  fedora_path_is_safe "$FEDORA_CONFIG_FILE" || return 1
  if [[ -L "$FEDORA_CONFIG_FILE" \
    || ( -e "$FEDORA_CONFIG_FILE" && ! -f "$FEDORA_CONFIG_FILE" ) ]]; then
    fedora_die "Refusing to overwrite an unsafe Fedora config file: $FEDORA_CONFIG_FILE"
    return 1
  fi
  config_dir="${FEDORA_CONFIG_FILE%/*}"
  [[ -n "$config_dir" ]] || config_dir=/
  [[ -d "$config_dir" && ! -L "$config_dir" ]] || return 1
  config_tmp="$(mktemp "$config_dir/.fedora-config.XXXXXX")" || return 1
  if ! {
    printf 'FEDORA_CONTAINER=%q\n' "$FEDORA_CONTAINER"
    printf 'FEDORA_IMAGE=%q\n' "$FEDORA_IMAGE"
    printf 'FEDORA_ARCH=%q\n' "$FEDORA_ARCH"
    printf 'FEDORA_DISPLAY=%q\n' "$FEDORA_DISPLAY"
    printf 'FEDORA_GPU_MODE=%q\n' "$FEDORA_GPU_MODE"
    printf 'FEDORA_AUDIO_MODE=%q\n' "$FEDORA_AUDIO_MODE"
    printf 'FEDORA_MEMORY_PROFILE=%q\n' "$FEDORA_MEMORY_PROFILE"
    printf 'FEDORA_LINUX_MODE_PROFILE=%q\n' "$FEDORA_LINUX_MODE_PROFILE"
    printf 'FEDORA_LINUX_MODE_AUTO_RESUME=%q\n' "$FEDORA_LINUX_MODE_AUTO_RESUME"
    printf 'FEDORA_ANDROID_APPS_MODE=%q\n' "$FEDORA_ANDROID_APPS_MODE"
    printf 'FEDORA_ANDROID_APPS_SCOPE=%q\n' "$FEDORA_ANDROID_APPS_SCOPE"
    printf 'FEDORA_ANDROID_BRIDGE_POLL_INTERVAL=%q\n' "$FEDORA_ANDROID_BRIDGE_POLL_INTERVAL"
    printf 'FEDORA_KEYBOARD_MODE=%q\n' "$FEDORA_KEYBOARD_MODE"
    printf 'FEDORA_SETTINGS_DAEMON=%q\n' "$FEDORA_SETTINGS_DAEMON"
    printf 'FEDORA_LAUNCH_TERMINAL=%q\n' "$FEDORA_LAUNCH_TERMINAL"
    printf 'FEDORA_KEYRING_MODE=%q\n' "$FEDORA_KEYRING_MODE"
    printf 'FEDORA_SEARCH_MODE=%q\n' "$FEDORA_SEARCH_MODE"
    printf 'FEDORA_PORTAL_MODE=%q\n' "$FEDORA_PORTAL_MODE"
    printf 'FEDORA_CALENDAR_MODE=%q\n' "$FEDORA_CALENDAR_MODE"
    printf 'FEDORA_USER=%q\n' "$FEDORA_USER"
    printf 'FEDORA_TERMUX_X11_FULLSCREEN=%q\n' "$FEDORA_TERMUX_X11_FULLSCREEN"
    printf 'FEDORA_NESTED_SCALE=%q\n' "$FEDORA_NESTED_SCALE"
    printf 'FEDORA_NESTED_MODE=%q\n' "$FEDORA_NESTED_MODE"
    printf 'FEDORA_NESTED_XWAYLAND=%q\n' "$FEDORA_NESTED_XWAYLAND"
    printf 'FEDORA_NESTED_MODE_SPECS=%q\n' "$FEDORA_NESTED_MODE_SPECS"
    printf 'FEDORA_DEVKIT_GDK_BACKEND=%q\n' "$FEDORA_DEVKIT_GDK_BACKEND"
    printf 'FEDORA_DEVKIT_PIPEWIRE=%q\n' "$FEDORA_DEVKIT_PIPEWIRE"
    printf 'FEDORA_DEVKIT_PIPEWIRE_CONFIG=%q\n' "$FEDORA_DEVKIT_PIPEWIRE_CONFIG"
    printf 'FEDORA_DEVKIT_DEBUG=%q\n' "$FEDORA_DEVKIT_DEBUG"
    printf 'FEDORA_SYSTEM_BUS_MODE=%q\n' "$FEDORA_SYSTEM_BUS_MODE"
    printf 'FEDORA_TERMUX_X11_LEGACY_DRAWING=%q\n' "$FEDORA_TERMUX_X11_LEGACY_DRAWING"
    printf 'FEDORA_TERMUX_X11_FORCE_BGRA=%q\n' "$FEDORA_TERMUX_X11_FORCE_BGRA"
    printf 'FEDORA_TERMUX_X11_AUTO_OPEN=%q\n' "$FEDORA_TERMUX_X11_AUTO_OPEN"
    printf 'FEDORA_CHECKOUT_ROOT=%q\n' "$FEDORA_CHECKOUT_ROOT"
    printf 'FEDORA_INSTALL_ROOT=%q\n' "$install_root"
    printf 'FEDORA_SHARED_STORAGE=%q\n' "$FEDORA_SHARED_STORAGE"
    printf 'FEDORA_GUEST_PROJECT_ROOT=%q\n' "$FEDORA_GUEST_PROJECT_ROOT"
  } > "$config_tmp"; then
    rm -f -- "$config_tmp"
    return 1
  fi
  chmod 600 "$config_tmp"
  [[ ! -L "$FEDORA_CONFIG_FILE" ]] || {
    rm -f -- "$config_tmp"
    fedora_die "Fedora config file became a symlink during update"
    return 1
  }
  mv -f -- "$config_tmp" "$FEDORA_CONFIG_FILE"
  [[ -f "$FEDORA_CONFIG_FILE" && ! -L "$FEDORA_CONFIG_FILE" ]] || return 1
  chmod 600 "$FEDORA_CONFIG_FILE"
}
write_config || {
  fedora_die "Could not write Fedora Shell configuration safely"
  exit 1
}

if ! fedora_container_exists; then
  fedora_log "Installing official OCI image $FEDORA_IMAGE for $FEDORA_ARCH as $FEDORA_CONTAINER."
  "$FEDORA_PD_BIN" install --architecture "$FEDORA_ARCH" --name "$FEDORA_CONTAINER" "$FEDORA_IMAGE"
else
  fedora_log "Container $FEDORA_CONTAINER already exists; preserving its data."
fi

fedora_init_state
if ! "$FEDORA_PD_BIN" list --image 2>&1 \
  | fedora_atomic_write "$FEDORA_STATE_DIR/proot-images.txt" 600; then
  fedora_warn "Could not record the proot image inventory atomically"
fi
if ! "$FEDORA_PD_BIN" list 2>&1 \
  | fedora_atomic_write "$FEDORA_STATE_DIR/proot-containers.txt" 600; then
  fedora_warn "Could not record the proot container inventory atomically"
fi

fedora_log "Installing GNOME packages inside Fedora. This can take a while under PRoot."
fedora_pd_login_root /usr/bin/env \
  "FEDORA_RELEASE=$FEDORA_RELEASE" \
  "FEDORA_USER=$FEDORA_USER" \
  /bin/bash "$FEDORA_GUEST_PROJECT_ROOT/fedora/rootfs/install-gnome.sh"

fedora_sync_guest_config

fedora_install_owned_file \
  "$install_root/integration/widget/fedora" \
  "$FEDORA_WIDGET_DIR/Fedora" \
  'fedora-shell-widget-v1'
if (( ENABLE_BOOT )); then
  fedora_install_owned_file \
    "$install_root/integration/boot/fedora-shell" \
    "$FEDORA_BOOT_DIR/fedora-shell" \
    'fedora-shell-boot-v1'
  fedora_log "Installed safe Termux:Boot observer; visible Fedora launch remains owned by the selected Home Activity."
elif [[ -f "$FEDORA_BOOT_DIR/fedora-shell" ]] \
  && grep -Fq 'fedora-shell-boot-v1' "$FEDORA_BOOT_DIR/fedora-shell"; then
  # Older releases used this owned path to start a hidden Fedora session after
  # boot. Replace that project-owned hook even without --enable-boot so an
  # update cannot leave a background RAM consumer behind.
  fedora_install_owned_file \
    "$install_root/integration/boot/fedora-shell" \
    "$FEDORA_BOOT_DIR/fedora-shell" \
    'fedora-shell-boot-v1'
  fedora_log "Replaced the old hidden Termux:Boot launcher with a safe observer."
fi

fedora_log "Running quick diagnostics. A non-zero optional probe does not change the install result."
if [[ -x "$install_root/scripts/diagnostics.sh" ]]; then
  "$install_root/scripts/diagnostics.sh" --quick || fedora_warn "Quick diagnostics reported an issue; see $FEDORA_LOG_DIR."
fi

cat <<EOF

Fedora Shell installation is complete.

Container: $FEDORA_CONTAINER
Installed control tree: $install_root
State and logs: $FEDORA_STATE_DIR

Next steps:
  1. Build/install the Android controller from android/ and complete its initial GUI setup.
  2. Install/open the compatible Termux:X11 APK once; keep device fullscreen off for bottom-swipe navigation and configure touch manually.
  3. Use Linux Mode -> ON in Fedora Shell, or run: $install_root/scripts/linux-mode.sh enable
  4. If the window is black, retry with: $install_root/scripts/start.sh --legacy-drawing
  5. For a shareable redacted report: $install_root/scripts/diagnostics.sh --full --redact

Memory profile: $FEDORA_MEMORY_PROFILE (12 GiB devices use the conservative profile automatically).

Android safety contract: this installer does not disable, delete, force-stop or
reconfigure Android packages, settings, services, LMKD or zRAM. Android remains
the host; the GUI can only ask the user to choose Fedora Shell as the Home app.

The GNOME session remains Wayland-first. Pure X11 requires explicit
FEDORA_ALLOW_X11=1 and is not enabled by this installer.
EOF
