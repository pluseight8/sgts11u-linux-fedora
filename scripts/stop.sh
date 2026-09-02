#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-stop-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"

FEDORA_ASSUME_YES="${FEDORA_ASSUME_YES:-0}"

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/stop.sh [--yes]

Stops only Fedora Shell's recorded container and project-owned transport
processes. Android and One UI are not modified.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --yes) FEDORA_ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fedora_die "Unknown option: $1"; exit 64 ;;
  esac
done

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_require_pd
fedora_init_state

# Stop the Termux-UID broker before stopping its Fedora client. This prevents
# an in-flight Android launch request from surviving container shutdown and
# being interpreted as a new request during the next session.
fedora_kill_owned_pid "$FEDORA_PID_DIR/android-bridge-broker.pid" android-bridge-broker.sh
android_bridge_dir="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/android-bridge"
for android_bridge_queue in "$android_bridge_dir/requests" "$android_bridge_dir/responses"; do
  if [[ -d "$android_bridge_queue" && ! -L "$android_bridge_queue" ]]; then
    find "$android_bridge_queue" -maxdepth 1 \( -type f -o -type l \) \
      -name '*.*' -delete 2>/dev/null || true
  fi
done

if fedora_container_exists && fedora_container_running; then
  fedora_log "Stopping only Fedora container '$FEDORA_CONTAINER'."
  "$FEDORA_PD_BIN" kill "$FEDORA_CONTAINER" || fedora_warn "PRoot-Distro did not report a clean stop."
else
  fedora_log "Fedora container is not running."
fi

fedora_kill_owned_pid "$FEDORA_PID_DIR/virgl.pid" virgl_test_server_android
fedora_kill_owned_pid "$FEDORA_PID_DIR/termux-x11.pid" termux-x11
rm -f -- "$FEDORA_PID_DIR/termux-x11.args"
if [[ -x "$FEDORA_INSTALL_ROOT/audio/stop.sh" ]]; then
  "$FEDORA_INSTALL_ROOT/audio/stop.sh" || true
fi

restore_guest_systemd_marker() {
  local result=""
  # start.sh performs this rename as Fedora guest root because the marker is
  # commonly root-owned. Repeat the restore during recovery so a hard-killed
  # Termux/PRoot supervisor cannot leave its Fedora-only backup orphaned.
  if ! fedora_container_exists; then
    return 0
  fi
  if ! result="$(fedora_pd_login_root /bin/bash -c '
    marker=/run/systemd/seats
    backup=/run/systemd/seats.fedora-shell-backup
    session_backup=/tmp/fedora-runtime/systemd-seats-marker
    restored=0
    conflict=0

    # fedora-session uses a runtime-local backup when it has to perform its
    # own cleanup. Recover both that path and the /run backup made by start.sh;
    # never delete a marker when the destination is occupied.
    for candidate in "$backup" "$session_backup"; do
      if [ -L "$candidate" ] || [ -L "$marker" ]; then
        conflict=1
        continue
      fi
      if [ ! -e "$candidate" ]; then
        continue
      fi
      if [ -e "$marker" ]; then
        conflict=1
        continue
      fi
      mv -- "$candidate" "$marker"
      restored=1
    done

    if [ "$conflict" -eq 1 ]; then
      printf "FEDORA_MARKER_STATE=conflict\n"
      exit 2
    elif [ "$restored" -eq 1 ]; then
      printf "FEDORA_MARKER_STATE=restored\n"
    else
      printf "FEDORA_MARKER_STATE=none\n"
    fi
  ' 2>&1)"; then
    fedora_warn "Could not restore Fedora-only systemd marker during recovery: ${result:0:512}"
    return 1
  fi
  if [[ "$result" == *FEDORA_MARKER_STATE=conflict* ]]; then
    fedora_warn "Did not overwrite a Fedora-only systemd marker created during the session"
  elif [[ "$result" == *FEDORA_MARKER_STATE=restored* ]]; then
    fedora_log "Restored Fedora-only /run/systemd/seats marker during recovery"
  fi
}
restore_guest_systemd_marker || true

restore_guest_fedora_settings() {
  local result=""
  local settings_backup="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/fedora-local-settings.backup"
  # fedora-session normally restores its temporary dconf tuning from its EXIT
  # trap. If the whole guest was terminated abruptly, recover the user-owned
  # backup in a fresh, private Fedora session bus. This remains Fedora-local;
  # no Android setting or process is inspected or changed.
  # The backup lives under shared-tmp, so avoid starting a PRoot command when
  # there is no recovery work to do. This keeps a normal OFF idempotent.
  if [[ -L "$settings_backup" \
    || ( -e "$settings_backup" && ! -f "$settings_backup" ) ]]; then
    fedora_warn "Refusing an unsafe Fedora-local dconf backup during recovery: $settings_backup"
    return 1
  fi
  [[ -r "$settings_backup" ]] || return 0
  if ! result="$(fedora_pd_login /usr/bin/dbus-run-session -- /bin/bash -c '
    backup=/tmp/fedora-runtime/fedora-local-settings.backup
    [ -L "$backup" ] && exit 2
    [ -e "$backup" ] && [ ! -f "$backup" ] && exit 2
    [ -r "$backup" ] || exit 0
    restored=1
    while IFS="|" read -r schema key value; do
      [ -n "$schema" ] && [ -n "$key" ] && [ -n "$value" ] || continue
      gsettings set "$schema" "$key" "$value" >/dev/null 2>&1 || restored=0
    done < "$backup"
    if [ "$restored" -eq 1 ]; then
      rm -f -- "$backup"
      printf "FEDORA_SETTINGS_STATE=restored\n"
    else
      printf "FEDORA_SETTINGS_STATE=retained\n"
      exit 2
    fi
  ' 2>&1)"; then
    fedora_warn "Could not restore Fedora-local dconf backup during stop: ${result:0:512}"
    return 1
  fi
  if [[ "$result" == *FEDORA_SETTINGS_STATE=restored* ]]; then
    fedora_log "Restored Fedora-local dconf values during recovery"
  elif [[ "$result" == *FEDORA_SETTINGS_STATE=retained* ]]; then
    fedora_warn "Fedora-local dconf backup remains for the next recovery attempt"
  fi
}
restore_guest_fedora_settings || true

rm -f -- "$FEDORA_STATE_DIR/session-host.env" \
  "$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/fedora-session-state.env"
if [[ -x "$FEDORA_INSTALL_ROOT/integration/android-memory-governor.sh" ]]; then
  "$FEDORA_INSTALL_ROOT/integration/android-memory-governor.sh" restore-evidence \
    >/dev/null 2>&1 || fedora_warn "Could not refresh the read-only Android policy receipt."
fi
fedora_log "Fedora Shell stopped. Android/One UI was not modified."
