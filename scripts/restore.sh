#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-restore-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/guest-config.sh"

FEDORA_ASSUME_YES="${FEDORA_ASSUME_YES:-0}"
archive=""

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/restore.sh [--yes] ROOTFS_BACKUP.tar.xz

The archive must have been created for the Fedora Shell container name.
Host-state archives are reported but never extracted automatically.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --yes) FEDORA_ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; exit 64 ;;
    *)
      [[ -z "$archive" ]] || { usage; exit 64; }
      archive="$1"
      shift
      ;;
  esac
done

[[ -n "$archive" ]] || { usage; exit 64; }
fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_require_pd
fedora_require_cmd tar
[[ -f "$archive" && ! -L "$archive" ]] || {
  fedora_die "Backup must be a regular, non-symlink file: $archive"
  exit 1
}

top_levels="$(tar -tf "$archive" 2>/dev/null | awk -F/ 'NF { print $1 }' | sort -u)"
[[ "$top_levels" == "$FEDORA_CONTAINER" ]] || {
  fedora_die "Refusing archive with unexpected top-level names. Expected only $FEDORA_CONTAINER, got: $top_levels"
  exit 1
}

if fedora_container_exists; then
  if ! fedora_confirm "Remove current Fedora container '$FEDORA_CONTAINER' and restore this archive?"; then
    fedora_die "Restore cancelled."
    exit 1
  fi
  stop_script="$FEDORA_INSTALL_ROOT/scripts/stop.sh"
  if [[ -x "$stop_script" && ! -L "$stop_script" ]]; then
    if ! bash "$stop_script" --yes; then
      fedora_die "Could not stop Fedora Shell cleanly; refusing destructive restore."
      exit 1
    fi
  else
    fedora_warn "Installed stop helper is unavailable; stopping recorded project transports directly."
    fedora_stop_owned_transports
  fi
  if fedora_container_running; then
    if ! "$FEDORA_PD_BIN" kill "$FEDORA_CONTAINER"; then
      fedora_die "Could not stop Fedora container '$FEDORA_CONTAINER'; refusing destructive restore."
      exit 1
    fi
  fi
  if fedora_container_running; then
    fedora_die "Fedora container '$FEDORA_CONTAINER' is still running; refusing destructive restore."
    exit 1
  fi
  "$FEDORA_PD_BIN" remove "$FEDORA_CONTAINER"
fi

fedora_log "Restoring $archive."
"$FEDORA_PD_BIN" restore "$archive"
fedora_sync_guest_config
fedora_log "Restore complete. Host-state archives must be inspected manually; no Android files were written."
printf 'restored_container=%s\n' "$FEDORA_CONTAINER"
