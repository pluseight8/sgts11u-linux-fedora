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

fedora_install_root_path_is_safe "$install_root" || {
  fedora_die "Refusing to remove an install root outside safe user data: $install_root"
  exit 1
}
fedora_user_data_path_is_safe "$FEDORA_STATE_DIR" || {
  fedora_die "Refusing to remove state outside safe user data: $FEDORA_STATE_DIR"
  exit 1
}

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
      # An installed-copy invocation has FEDORA_PROJECT_ROOT equal to the
      # marked install root and is allowed to remove that exact tree. A real
      # checkout (including a Git worktree whose .git is a file) remains
      # protected, as does every child of it.
      if [[ "$install_root" != "$FEDORA_PROJECT_ROOT" || -e "$FEDORA_PROJECT_ROOT/.git" ]]; then
        fedora_die "Install root is the checkout or inside it; refusing deletion: $install_root"
        exit 1
      fi
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
  [[ ! -L "$FEDORA_STATE_DIR" ]] || {
    fedora_die "Refusing to remove symlinked state directory: $FEDORA_STATE_DIR"
    exit 1
  }
  if [[ "$FEDORA_STATE_DIR" != "$FEDORA_USER_HOME/.fedora-shell" ]]; then
    if [[ ! -f "$FEDORA_STATE_DIR/config.env" ]] || ! grep -Fq 'FEDORA_CONTAINER=' "$FEDORA_STATE_DIR/config.env"; then
      fedora_die "Refusing to remove custom state directory without a Fedora Shell config: $FEDORA_STATE_DIR"
      exit 1
    fi
  fi
fi

remove_install_tree() {
  local item target unknown=0

  [[ -d "$install_root" && ! -L "$install_root" ]] || return 0

  # fedora_sync_project_tree deliberately preserves unrelated top-level files
  # in the installation directory.  Uninstall must honor that contract too;
  # never turn an explicit project removal into rm -rf of the whole directory.
  while IFS= read -r -d '' target; do
    item="${target##*/}"
    case "$item" in
      .fedora-shell-install)
        ;;
      scripts|config|fedora|gpu|audio|input|integration|README.md|AUDIT.md|\
      ARCHITECTURE.md|INSTALL.md|SECURITY.md|STATUS.md|TROUBLESHOOTING.md|VERSIONS.md)
        ;;
      *)
        unknown=1
        fedora_warn "Preserving unrecognized file in install root: $target"
        ;;
    esac
  done < <(find "$install_root" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

  for item in "${FEDORA_PROJECT_ITEMS[@]}"; do
    target="$install_root/$item"
    [[ -e "$target" || -L "$target" ]] || continue
    if [[ -L "$target" ]]; then
      fedora_die "Refusing to remove symlinked project item: $target"
      return 1
    fi
    if [[ -d "$target" ]]; then
      rm -rf -- "$target"
    elif [[ -f "$target" ]]; then
      rm -f -- "$target"
    else
      fedora_die "Refusing to remove non-regular project item: $target"
      return 1
    fi
  done
  if [[ -e "$install_marker" || -L "$install_marker" ]]; then
    [[ ! -L "$install_marker" && -f "$install_marker" ]] || {
      fedora_die "Refusing to remove unsafe install marker: $install_marker"
      return 1
    }
    rm -f -- "$install_marker"
  fi
  if (( unknown == 0 )); then
    rmdir "$install_root" 2>/dev/null || fedora_warn "Install root is not empty; preserving it: $install_root"
  else
    fedora_log "Preserved unrecognized install-root files; removed only Fedora Shell project items."
  fi
}

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

# Stop the installed supervisor first so no project-owned transport keeps
# using the container/control tree while it is being removed. If an older or
# damaged install has no helper, use the PID-file/command-marker fallback.
stop_script="$install_root/scripts/stop.sh"
if [[ -x "$stop_script" && ! -L "$stop_script" ]]; then
  if ! bash "$stop_script" --yes; then
    fedora_die "Could not stop Fedora Shell cleanly; refusing destructive uninstall."
    exit 1
  fi
else
  fedora_warn "Installed stop helper is unavailable; stopping recorded project transports directly."
  fedora_stop_owned_transports
fi

pd_bin="$(fedora_pd_bin 2>/dev/null || true)"
if [[ -n "$pd_bin" ]] && fedora_container_exists; then
  if fedora_container_running; then
    if ! "$pd_bin" kill "$FEDORA_CONTAINER"; then
      fedora_die "Could not stop Fedora container '$FEDORA_CONTAINER'; refusing destructive uninstall."
      exit 1
    fi
  fi
  if fedora_container_running; then
    fedora_die "Fedora container '$FEDORA_CONTAINER' is still running; refusing destructive uninstall."
    exit 1
  fi
  fedora_log "Removing only container '$FEDORA_CONTAINER'."
  "$pd_bin" remove "$FEDORA_CONTAINER"
else
  fedora_warn "PRoot-Distro/container was not found; continuing with project-owned files."
fi

fedora_remove_owned_file "$FEDORA_WIDGET_DIR/Fedora" fedora-shell-widget-v1
fedora_remove_owned_file "$FEDORA_BOOT_DIR/fedora-shell" fedora-shell-boot-v1

if [[ -e "$install_root" ]]; then
  remove_install_tree
  fedora_log "Removed project-owned installed tree items: $install_root"
fi

if [[ -d "$FEDORA_STATE_DIR" ]]; then
  rm -rf -- "$FEDORA_STATE_DIR"
  fedora_log "Removed project-owned state and logs: $FEDORA_STATE_DIR"
fi

printf '%s\n' 'Fedora Shell was uninstalled. Termux, Termux:X11, Android, One UI and backups were left untouched.'
