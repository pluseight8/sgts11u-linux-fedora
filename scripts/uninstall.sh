#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-uninstaller-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"

FEDORA_ASSUME_YES="${FEDORA_ASSUME_YES:-0}"
DRY_RUN=0
while (( $# > 0 )); do
  case "$1" in
    --yes) FEDORA_ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      printf '%s\n' 'Usage: ./scripts/uninstall.sh [--yes] [--dry-run]'
      exit 0
      ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 64 ;;
  esac
done

fedora_init_log
fedora_require_termux
fedora_require_non_root
install_root="$(fedora_install_root)"
install_marker="$install_root/.fedora-shell-install"

# Preflight every target before removing the container. If a user-owned file
# is found, the uninstall stops before any destructive action is taken.
if [[ -e "$install_root" || -L "$install_root" ]]; then
  [[ -d "$install_root" && ! -L "$install_root" ]] || {
    fedora_die "Refusing to remove non-directory or symlink install root: $install_root"
    exit 1
  }
  [[ -f "$install_marker" ]] || {
    fedora_die "Refusing to remove unmarked install root: $install_root"
    exit 1
  }
  grep -Fq '# fedora-shell-install-marker-v1' "$install_marker" || {
    fedora_die "Install root marker is not owned by Fedora Shell: $install_root"
    exit 1
  }
  case "$install_root" in
    "$FEDORA_PROJECT_ROOT"|"$FEDORA_PROJECT_ROOT"/*)
      fedora_die "Install root is the checkout or inside it; refusing deletion: $install_root"
      exit 1
      ;;
  esac
fi

for owned_target in "$FEDORA_WIDGET_DIR/Fedora" "$FEDORA_BOOT_DIR/fedora-shell"; do
  if [[ -L "$owned_target" ]]; then
    fedora_die "Refusing to remove symlink: $owned_target"
    exit 1
  fi
  if [[ -e "$owned_target" ]]; then
    [[ -f "$owned_target" ]] || { fedora_die "Refusing to remove non-file: $owned_target"; exit 1; }
  fi
done
if [[ -e "$FEDORA_WIDGET_DIR/Fedora" ]] && ! grep -Fq 'fedora-shell-widget-v1' "$FEDORA_WIDGET_DIR/Fedora"; then
  fedora_die "Refusing to remove unowned file: $FEDORA_WIDGET_DIR/Fedora"
  exit 1
fi
if [[ -e "$FEDORA_BOOT_DIR/fedora-shell" ]] && ! grep -Fq 'fedora-shell-boot-v1' "$FEDORA_BOOT_DIR/fedora-shell"; then
  fedora_die "Refusing to remove unowned file: $FEDORA_BOOT_DIR/fedora-shell"
  exit 1
fi

if [[ -d "$FEDORA_STATE_DIR" ]]; then
  if [[ "$FEDORA_STATE_DIR" != "$FEDORA_USER_HOME/.fedora-shell" ]]; then
    if [[ ! -f "$FEDORA_STATE_DIR/config.env" ]] || ! grep -Fq 'FEDORA_CONTAINER=' "$FEDORA_STATE_DIR/config.env"; then
      fedora_die "Refusing to remove custom state directory without a Fedora Shell config: $FEDORA_STATE_DIR"
      exit 1
    fi
  fi
fi

if (( DRY_RUN )); then
  printf '%s\n' 'Fedora Shell uninstall preview:'
  printf '  container: %s\n' "$FEDORA_CONTAINER"
  printf '  install_root: %s\n' "$install_root"
  printf '  state_dir: %s\n' "$FEDORA_STATE_DIR"
  printf '  widget_shortcut: %s\n' "$FEDORA_WIDGET_DIR/Fedora"
  printf '  boot_hook: %s\n' "$FEDORA_BOOT_DIR/fedora-shell"
  printf '%s\n' 'Backups, the checkout, Termux packages, Android and One UI are kept.'
  exit 0
fi

if ! fedora_confirm "Remove Fedora container, Fedora Shell state and owned shortcuts? Backups and the checkout are kept."; then
  fedora_die "Uninstall cancelled."
  exit 1
fi

pd_bin="$(fedora_pd_bin 2>/dev/null || true)"
if [[ -n "$pd_bin" ]] && fedora_container_exists; then
  if fedora_container_running; then
    "$pd_bin" kill "$FEDORA_CONTAINER" || true
  fi
  fedora_log "Removing only container '$FEDORA_CONTAINER'."
  "$pd_bin" remove "$FEDORA_CONTAINER"
else
  fedora_warn "PRoot-Distro/container was not found; continuing with project-owned files."
fi

fedora_remove_owned_file "$FEDORA_WIDGET_DIR/Fedora" fedora-shell-widget-v1
fedora_remove_owned_file "$FEDORA_BOOT_DIR/fedora-shell" fedora-shell-boot-v1

if [[ -e "$install_root" ]]; then
  rm -rf -- "$install_root"
  fedora_log "Removed project-owned installed tree: $install_root"
fi

if [[ -d "$FEDORA_STATE_DIR" ]]; then
  rm -rf -- "$FEDORA_STATE_DIR"
  fedora_log "Removed project-owned state and logs: $FEDORA_STATE_DIR"
fi

printf '%s\n' 'Fedora Shell was uninstalled. Termux, Termux:X11, Android, One UI and backups were left untouched.'
