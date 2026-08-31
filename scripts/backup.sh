#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-backup-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"

FEDORA_ASSUME_YES="${FEDORA_ASSUME_YES:-0}"
BACKUP_DIR="${BACKUP_DIR:-}"

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/backup.sh [--yes] [--output DIRECTORY]

The container must be stopped first. Backups are not encrypted by this script.
The default destination is shared storage/FedoraBackups when available.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --yes) FEDORA_ASSUME_YES=1; shift ;;
    --output)
      (( $# >= 2 )) || { usage; exit 64; }
      BACKUP_DIR="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
done

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_require_container
fedora_require_cmd tar
fedora_require_cmd sha256sum

if fedora_container_running; then
  fedora_die "Container is running. Stop it before backup so no live process state is mistaken for a consistent snapshot."
  exit 1
fi

if [[ -z "$BACKUP_DIR" ]]; then
  if [[ -d "$FEDORA_SHARED_STORAGE" ]]; then
    BACKUP_DIR="$FEDORA_SHARED_STORAGE/FedoraBackups"
  else
    BACKUP_DIR="$FEDORA_USER_HOME/FedoraBackups"
  fi
fi
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR" 2>/dev/null || true

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$BACKUP_DIR/${FEDORA_CONTAINER}-${timestamp}.tar.xz"
host_archive="$BACKUP_DIR/${FEDORA_CONTAINER}-${timestamp}.host.tar.xz"
manifest="$BACKUP_DIR/${FEDORA_CONTAINER}-${timestamp}.manifest.txt"
for path in "$archive" "$host_archive" "$manifest"; do
  [[ ! -e "$path" ]] || { fedora_die "Refusing to overwrite existing backup: $path"; exit 1; }
done

fedora_log "Archiving container $FEDORA_CONTAINER to $archive."
"$FEDORA_PD_BIN" backup "$FEDORA_CONTAINER" --output "$archive"

host_items=()
for item in config.env install-device-probe.env proot-images.txt proot-containers.txt; do
  [[ -f "$FEDORA_STATE_DIR/$item" ]] && host_items+=("$item")
done
if (( ${#host_items[@]} > 0 )); then
  tar -cJf "$host_archive" -C "$FEDORA_STATE_DIR" "${host_items[@]}"
else
  fedora_warn "No host state files were present; creating an empty metadata archive was skipped."
  host_archive=""
fi

{
  printf 'fedora-shell-backup-v1\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'container=%s\n' "$FEDORA_CONTAINER"
  printf 'image=%s\n' "$FEDORA_IMAGE"
  printf 'architecture=%s\n' "$FEDORA_ARCH"
  printf 'rootfs_archive=%s\n' "$archive"
  [[ -n "$host_archive" ]] && printf 'host_state_archive=%s\n' "$host_archive"
  printf '\n[sha256]\n'
  sha256sum "$archive"
  [[ -n "$host_archive" ]] && sha256sum "$host_archive"
} > "$manifest"
chmod 600 "$archive" "$manifest"
[[ -z "$host_archive" ]] || chmod 600 "$host_archive"
fedora_log "Backup complete. Rootfs processes are not preserved; keep the manifest with the archives."
printf 'rootfs_archive=%s\n' "$archive"
[[ -z "$host_archive" ]] || printf 'host_state_archive=%s\n' "$host_archive"
printf 'manifest=%s\n' "$manifest"
