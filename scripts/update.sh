#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-update-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/guest-config.sh"

FEDORA_ASSUME_YES="${FEDORA_ASSUME_YES:-0}"
MAKE_BACKUP=1
UPDATE_TERMUX=1

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/update.sh [--yes] [--no-backup] [--no-termux]

Updates Termux packages and Fedora packages without changing Fedora release
or replacing the GPU stack. A rootfs backup is made by default. Use
--no-termux to update only the Fedora container.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --yes) FEDORA_ASSUME_YES=1; shift ;;
    --no-backup) MAKE_BACKUP=0; shift ;;
    --no-termux) UPDATE_TERMUX=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_require_container

if fedora_container_running; then
  "$FEDORA_ENTRY_DIR/stop.sh" --yes
fi
if (( MAKE_BACKUP )); then
  "$FEDORA_ENTRY_DIR/backup.sh" --yes
else
  fedora_warn "Skipping backup because --no-backup was explicitly supplied."
fi

if (( UPDATE_TERMUX )); then
  fedora_log "Updating Termux packages."
  pkg update -y
  pkg upgrade -y
else
  fedora_log "Skipping Termux package update (--no-termux)."
fi

fedora_log "Updating Fedora packages inside the existing container."
fedora_pd_login_root /usr/bin/dnf -y upgrade --refresh --setopt=install_weak_deps=False
fedora_pd_login_root /usr/bin/dnf -y clean all
fedora_sync_guest_config
"$FEDORA_PD_BIN" list --image > "$FEDORA_STATE_DIR/proot-images.txt" 2>&1 || true
"$FEDORA_PD_BIN" list > "$FEDORA_STATE_DIR/proot-containers.txt" 2>&1 || true
chmod 600 "$FEDORA_STATE_DIR/proot-images.txt" "$FEDORA_STATE_DIR/proot-containers.txt"
fedora_log "Update complete. Run diagnostics before changing FEDORA_GPU_MODE."
