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
MIN_FREE_GIB=12

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/install.sh [OPTIONS]

Options:
  --yes                    accept installer confirmations
  --allow-unknown-device  continue when the Android model is not recognised
  --enable-boot            install the optional Termux:Boot hook
  --skip-x11-package       do not install termux-x11-nightly from x11-repo
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

fedora_init_log
fedora_require_termux
fedora_require_non_root
for required_command in pkg uname df awk mkdir cp chmod date; do
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
android_release="$(fedora_getprop ro.build.version.release)"
android_api="$(fedora_getprop ro.build.version.sdk)"
device_ok=0
case "$device_model" in
  SM-X930|SM-X936|SM-X936*) device_ok=1 ;;
esac
if (( ! device_ok && ! ALLOW_UNKNOWN_DEVICE )); then
  fedora_die "Unrecognised model '$device_model'. Use --allow-unknown-device only for research on a compatible ARM64 device."
  exit 1
fi

free_kib="$(fedora_free_kib "$FEDORA_USER_HOME")"
min_free_kib="$(awk -v gib="$MIN_FREE_GIB" 'BEGIN { printf "%.0f", gib * 1024 * 1024 }')"
if [[ "$free_kib" =~ ^[0-9]+$ ]] && (( free_kib < min_free_kib )); then
  fedora_die "At least ${MIN_FREE_GIB} GiB is required; only $((free_kib / 1024 / 1024)) GiB is free."
  exit 1
fi

fedora_log "Device: ${device_manufacturer:-unknown} ${device_model:-unknown}; Android ${android_release:-unknown} (API ${android_api:-unknown}); host ${host_arch}."
fedora_log "Free space check: ${free_kib:-unknown} KiB available; ${MIN_FREE_GIB} GiB requested."

fedora_init_state
{
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'manufacturer=%q\n' "$device_manufacturer"
  printf 'model=%q\n' "$device_model"
  printf 'android_release=%q\n' "$android_release"
  printf 'android_api=%q\n' "$android_api"
  printf 'host_arch=%q\n' "$host_arch"
  printf 'free_kib=%q\n' "${free_kib:-unknown}"
} > "$FEDORA_STATE_DIR/install-device-probe.env"
chmod 600 "$FEDORA_STATE_DIR/install-device-probe.env"

if ! fedora_confirm "Install/update Termux packages and the Fedora container now?"; then
  fedora_die "Installation cancelled."
  exit 1
fi

pkg update -y
pkg install -y proot-distro termux-api
if (( ! SKIP_X11_PACKAGE )); then
  pkg install -y x11-repo
  pkg install -y termux-x11-nightly
else
  fedora_warn "Skipping termux-x11-nightly; start.sh will require a manually installed compatible X11 package."
fi

fedora_require_pd
install_root="$(fedora_install_root)"
install_marker="$install_root/.fedora-shell-install"
if [[ -e "$install_root" && ! -f "$install_marker" ]]; then
  fedora_die "Refusing to use existing non-project directory: $install_root"
  exit 1
fi
mkdir -p "$install_root"
if [[ ! -f "$install_marker" ]]; then
  {
    printf '%s\n' '# fedora-shell-install-marker-v1'
    printf 'installed_by=%q\n' "$FEDORA_PROJECT_ROOT/scripts/install.sh"
  } > "$install_marker"
  chmod 600 "$install_marker"
fi

# Keep an installed copy so the one-tap shortcut remains usable after the
# checkout is moved or deleted. Existing project-owned files are updated;
# unrelated files in the installation directory are never removed.
project_items=(
  scripts
  fedora
  gpu
  audio
  input
  integration
  README.md
  ARCHITECTURE.md
  INSTALL.md
  SECURITY.md
  STATUS.md
  TROUBLESHOOTING.md
  VERSIONS.md
)
if [[ "$install_root" != "$FEDORA_PROJECT_ROOT" ]]; then
  for item in "${project_items[@]}"; do
    [[ -e "$FEDORA_PROJECT_ROOT/$item" ]] || {
      fedora_die "Project file is missing: $FEDORA_PROJECT_ROOT/$item"
      exit 1
    }
    cp -R "$FEDORA_PROJECT_ROOT/$item" "$install_root/"
  done
fi

write_config() {
  umask 077
  {
    printf 'FEDORA_CONTAINER=%q\n' "$FEDORA_CONTAINER"
    printf 'FEDORA_IMAGE=%q\n' "$FEDORA_IMAGE"
    printf 'FEDORA_ARCH=%q\n' "$FEDORA_ARCH"
    printf 'FEDORA_DISPLAY=%q\n' "$FEDORA_DISPLAY"
    printf 'FEDORA_GPU_MODE=%q\n' "$FEDORA_GPU_MODE"
    printf 'FEDORA_AUDIO_MODE=%q\n' "$FEDORA_AUDIO_MODE"
    printf 'FEDORA_USER=%q\n' "$FEDORA_USER"
    printf 'FEDORA_TERMUX_X11_FULLSCREEN=%q\n' "$FEDORA_TERMUX_X11_FULLSCREEN"
    printf 'FEDORA_NESTED_SCALE=%q\n' "$FEDORA_NESTED_SCALE"
    printf 'FEDORA_NESTED_MODE=%q\n' "$FEDORA_NESTED_MODE"
    printf 'FEDORA_INSTALL_ROOT=%q\n' "$install_root"
    printf 'FEDORA_SHARED_STORAGE=%q\n' "$FEDORA_SHARED_STORAGE"
    printf 'FEDORA_GUEST_PROJECT_ROOT=%q\n' "$FEDORA_GUEST_PROJECT_ROOT"
  } > "$FEDORA_CONFIG_FILE"
  chmod 600 "$FEDORA_CONFIG_FILE"
}
write_config

if ! fedora_container_exists; then
  fedora_log "Installing official OCI image $FEDORA_IMAGE for $FEDORA_ARCH as $FEDORA_CONTAINER."
  "$FEDORA_PD_BIN" install --architecture "$FEDORA_ARCH" --name "$FEDORA_CONTAINER" "$FEDORA_IMAGE"
else
  fedora_log "Container $FEDORA_CONTAINER already exists; preserving its data."
fi

fedora_init_state
"$FEDORA_PD_BIN" list --image > "$FEDORA_STATE_DIR/proot-images.txt" 2>&1 || true
"$FEDORA_PD_BIN" list > "$FEDORA_STATE_DIR/proot-containers.txt" 2>&1 || true
chmod 600 "$FEDORA_STATE_DIR/proot-images.txt" "$FEDORA_STATE_DIR/proot-containers.txt"

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
  fedora_log "Installed optional Termux:Boot hook. Android battery/background policy may still require manual action."
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
  1. Open Termux:X11 once and confirm its fullscreen/touch preferences.
  2. Run: $install_root/scripts/start.sh
  3. If the window is black, run: $install_root/scripts/diagnostics.sh --full

The GNOME session remains Wayland-first. Pure X11 requires explicit
FEDORA_ALLOW_X11=1 and is not enabled by this installer.
EOF
