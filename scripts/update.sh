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
UPDATE_PROJECT=1

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/update.sh [--yes] [--no-backup] [--no-termux] [--no-project]

Updates the Fedora Shell checkout (when it is a clean main-branch clone), the
installed control tree, Termux packages and Fedora packages without changing
the Fedora release or replacing the GPU stack. A rootfs backup is made by
default. Use --no-project to keep the installed scripts unchanged, or
--no-termux to update only Fedora and project files.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --yes) FEDORA_ASSUME_YES=1; shift ;;
    --no-backup) MAKE_BACKUP=0; shift ;;
    --no-termux) UPDATE_TERMUX=0; shift ;;
    --no-project) UPDATE_PROJECT=0; shift ;;
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

if (( UPDATE_PROJECT )); then
  checkout_root="$FEDORA_CHECKOUT_ROOT"
  project_ready=1
  if [[ ! -d "$checkout_root/.git" ]]; then
    fedora_warn "Project checkout is unavailable at $checkout_root; keeping the installed control tree unchanged."
    project_ready=0
  else
    remote_url="$(git -C "$checkout_root" remote get-url origin 2>/dev/null || true)"
    case "$remote_url" in
      https://github.com/pluseight8/sgts11u-linux-fedora.git|https://github.com/pluseight8/sgts11u-linux-fedora|git@github.com:pluseight8/sgts11u-linux-fedora.git) ;;
      *)
        fedora_warn "Refusing to pull unexpected project origin at $checkout_root: ${remote_url:-<none>}"
        project_ready=0
        ;;
    esac
    current_branch="$(git -C "$checkout_root" symbolic-ref --short -q HEAD || true)"
    if (( project_ready )) && [[ "$current_branch" != main ]]; then
      fedora_warn "Project checkout is on '${current_branch:-detached HEAD}', not main; keeping it unchanged."
      project_ready=0
    fi
    if (( project_ready )) && [[ -n "$(git -C "$checkout_root" status --porcelain 2>/dev/null)" ]]; then
      fedora_warn "Project checkout has local changes; skipping pull and installed-tree sync to protect them: $checkout_root"
      project_ready=0
    fi
    if (( project_ready )); then
      fedora_log "Updating Fedora Shell checkout: $checkout_root"
      if ! git -C "$checkout_root" pull --ff-only; then
        fedora_warn "Project checkout update failed; keeping the installed control tree unchanged."
        project_ready=0
      fi
    fi
  fi
  if (( project_ready )); then
    fedora_repair_project_modes "$checkout_root"
    fedora_log "Synchronizing project scripts and configuration into $FEDORA_INSTALL_ROOT."
    fedora_sync_project_tree "$checkout_root" "$FEDORA_INSTALL_ROOT"
  fi
else
  fedora_log "Skipping project checkout/control-tree update (--no-project)."
fi

if (( UPDATE_TERMUX )); then
  fedora_log "Updating Termux packages."
  pkg update -y
  fedora_termux_full_upgrade
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
