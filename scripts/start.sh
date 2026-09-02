#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-start-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"

LEGACY_DRAWING=0
FORCE_BGRA=0
# Termux:X11 documents -legacy-drawing as the compatibility path for devices
# that show only a black surface. Keep the CLI flag, but also honor the
# documented environment variable so a launcher can persist the workaround.
if fedora_is_true "${TERMUX_X11_LEGACY_DRAWING:-${FEDORA_TERMUX_X11_LEGACY_DRAWING:-0}}"; then
  LEGACY_DRAWING=1
fi
if fedora_is_true "${TERMUX_X11_FORCE_BGRA:-${FEDORA_TERMUX_X11_FORCE_BGRA:-0}}"; then
  FORCE_BGRA=1
fi
LEAVE_TRANSPORT=0

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/start.sh [OPTIONS]

Options:
  --legacy-drawing  pass Termux:X11 -legacy-drawing (black-screen compatibility)
  --force-bgra      pass Termux:X11 -force-bgra (diagnostic only)
  --reconnect       reconnect to a running Fedora session and leave transport up
  -h, --help        show this help
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --legacy-drawing) LEGACY_DRAWING=1; shift ;;
    --force-bgra) FORCE_BGRA=1; shift ;;
    --reconnect) LEAVE_TRANSPORT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fedora_die "Unknown option: $1"; exit 64 ;;
  esac
done

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_require_container
fedora_have_cmd termux-x11 || { fedora_die "termux-x11 is missing. Install termux-x11-nightly or rerun install.sh."; exit 1; }
if [[ -x /system/bin/pm || -x /system/bin/cmd ]]; then
  if fedora_android_package_installed com.termux.x11; then
    fedora_log "Read-only check confirms the Termux:X11 Android package is installed."
  else
    package_check_rc=$?
    fedora_warn "Could not confirm com.termux.x11 through the read-only Android package API (rc=$package_check_rc); continuing because Android 16/vendor builds may restrict pm/cmd. The Termux:X11 socket check remains authoritative."
  fi
fi

if [[ ! "$FEDORA_DISPLAY" =~ ^:[0-9]+$ ]]; then
  fedora_die "FEDORA_DISPLAY must look like :0 or :1; got '$FEDORA_DISPLAY'"
  exit 64
fi
if ! fedora_keyboard_mode_valid "$FEDORA_KEYBOARD_MODE"; then
  fedora_warn "Unknown FEDORA_KEYBOARD_MODE=$FEDORA_KEYBOARD_MODE; using Linux focused-input mode"
  FEDORA_KEYBOARD_MODE=linux
fi

x11_pid_file="$FEDORA_PID_DIR/termux-x11.pid"
x11_args_file="$FEDORA_PID_DIR/termux-x11.args"
virgl_pid_file="$FEDORA_PID_DIR/virgl.pid"
android_bridge_pid_file="$FEDORA_PID_DIR/android-bridge-broker.pid"
android_bridge_dir="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/android-bridge"
android_bridge_script="$FEDORA_INSTALL_ROOT/integration/android-bridge-broker.sh"
session_state_host="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/fedora-session-state.env"
guest_systemd_marker_masked=0
marker_preflight_attempted=0

linux_mode_stop_requested() {
  # linux-mode.sh passes the shared-tmp guest spelling to fedora-session and
  # keeps a host spelling for this Termux-side preflight. Check both so direct
  # launches and concurrent ON/OFF transitions remain safe.
  if [[ -n "${FEDORA_LINUX_MODE_STOP_REQUEST_HOST:-}" ]] \
    && [[ -f "$FEDORA_LINUX_MODE_STOP_REQUEST_HOST" \
    && ! -L "$FEDORA_LINUX_MODE_STOP_REQUEST_HOST" ]]; then
    return 0
  fi
  [[ -n "${FEDORA_LINUX_MODE_STOP_REQUEST:-}" ]] \
    && [[ -f "$FEDORA_LINUX_MODE_STOP_REQUEST" \
    && ! -L "$FEDORA_LINUX_MODE_STOP_REQUEST" ]]
}

prepare_guest_systemd_marker() {
  local result=""
  # GNOME Shell detects systemd by the existence of /run/systemd/seats. That
  # marker can be root-owned in the Fedora guest, so do the temporary rename as
  # PRoot guest root, not as the ordinary Fedora desktop user. This only changes
  # one path in the disposable Fedora userspace and never touches Android /run.
  if ! result="$(fedora_pd_login_root /bin/bash -c '
    marker=/run/systemd/seats
    backup=/run/systemd/seats.fedora-shell-backup
    pid1=""
    [ -r /proc/1/comm ] && pid1="$(cat /proc/1/comm)"
    if [ "$pid1" = systemd ]; then
      printf "FEDORA_MARKER_STATE=real-systemd\n"
      exit 0
    fi
    if [ -L "$marker" ] || [ -L "$backup" ]; then
      printf "FEDORA_MARKER_STATE=unsafe\n"
      exit 2
    fi
    if [ -e "$marker" ] && [ -e "$backup" ]; then
      printf "FEDORA_MARKER_STATE=conflict\n"
      exit 2
    fi
    if [ -e "$marker" ]; then
      mv -- "$marker" "$backup"
      printf "FEDORA_MARKER_STATE=masked\n"
    elif [ -e "$backup" ]; then
      printf "FEDORA_MARKER_STATE=interrupted-mask\n"
    else
      printf "FEDORA_MARKER_STATE=absent\n"
    fi
  ' 2>&1)"; then
    fedora_die "Could not inspect/mask the Fedora-only systemd marker: ${result:0:512}"
    return 1
  fi
  if [[ "$result" == *FEDORA_MARKER_STATE=conflict* ]]; then
    fedora_die "Conflicting Fedora-only systemd marker backup exists; refusing to start GNOME"
    return 1
  fi
  if [[ "$result" == *FEDORA_MARKER_STATE=unsafe* ]]; then
    fedora_die "Unsafe Fedora-only systemd marker path is symlinked; refusing to start GNOME"
    return 1
  fi
  if [[ "$result" == *FEDORA_MARKER_STATE=masked* \
    || "$result" == *FEDORA_MARKER_STATE=interrupted-mask* ]]; then
    guest_systemd_marker_masked=1
    fedora_log "PRoot-only stale /run/systemd/seats marker is masked for this GNOME session"
  elif [[ "$result" == *FEDORA_MARKER_STATE=real-systemd* ]]; then
    fedora_log "Fedora guest reports a real systemd PID 1; leaving its marker untouched"
  fi
}

restore_guest_systemd_marker() {
  local result=""
  if ! result="$(fedora_pd_login_root /bin/bash -c '
    marker=/run/systemd/seats
    backup=/run/systemd/seats.fedora-shell-backup
    if [ -L "$marker" ] || [ -L "$backup" ]; then
      printf "FEDORA_MARKER_STATE=unsafe\n"
      exit 2
    fi
    if [ -e "$backup" ] && [ ! -e "$marker" ]; then
      mv -- "$backup" "$marker"
      printf "FEDORA_MARKER_STATE=restored\n"
    elif [ -e "$backup" ] && [ -e "$marker" ]; then
      printf "FEDORA_MARKER_STATE=conflict\n"
      exit 2
    else
      printf "FEDORA_MARKER_STATE=none\n"
    fi
  ' 2>&1)"; then
    fedora_warn "Could not restore Fedora-only systemd marker: ${result:0:512}"
    return 1
  fi
  if [[ "$result" == *FEDORA_MARKER_STATE=conflict* ]]; then
    fedora_warn "Did not overwrite a Fedora-only systemd marker created during the session"
  elif [[ "$result" == *FEDORA_MARKER_STATE=unsafe* ]]; then
    fedora_warn "Did not recover a symlinked Fedora-only systemd marker path"
  elif [[ "$result" == *FEDORA_MARKER_STATE=restored* ]]; then
    fedora_log "Restored Fedora-only /run/systemd/seats marker"
  fi
}

open_x11_activity() {
  local android_api=""
  local am_bin=""
  local am_output=""

  # Android 12+ restricts background activity launches. On the target Android
  # 16/One UI device, calling `am start` from Termux only produces a noisy
  # SecurityException and cannot make the window visible. Opening the APK is a
  # deliberate user action and is the reliable path. Keep an explicit `on`
  # escape hatch for older or specially configured devices.
  case "${FEDORA_TERMUX_X11_AUTO_OPEN:-auto}" in
    off|disabled|none|0|false|no)
      fedora_log "Automatic Termux:X11 activity launch disabled; open the APK manually."
      return 0
      ;;
    auto)
      android_api="$(fedora_getprop ro.build.version.sdk)"
      if [[ "$android_api" =~ ^[0-9]+$ ]] && (( android_api >= 31 )); then
        fedora_log "Android API $android_api restricts automatic Termux:X11 activity launch; open the APK manually."
        return 0
      fi
      ;;
    on|enabled|1|true|yes)
      ;;
    *)
      fedora_warn "Unknown FEDORA_TERMUX_X11_AUTO_OPEN=${FEDORA_TERMUX_X11_AUTO_OPEN}; open Termux:X11 manually."
      return 0
      ;;
  esac

  if [[ -x /system/bin/am ]]; then
    am_bin=/system/bin/am
  elif fedora_have_cmd am; then
    am_bin="$(command -v am)"
  fi
  if [[ -n "$am_bin" ]]; then
    if ! am_output="$("$am_bin" start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>&1)"; then
      am_output="$(printf '%s' "$am_output" | tr '\n' ' ')"
      fedora_warn "Could not open Termux:X11 activity automatically: ${am_output:0:512}"
      fedora_warn "Open the Termux:X11 APK manually; its APK and Termux package must come from the same release source."
    fi
    [[ -z "$am_output" ]] || printf '[x11-activity] %s\n' "$am_output" >> "$FEDORA_LOG_FILE"
  else
    fedora_warn "Android am command is unavailable; open Termux:X11 manually."
  fi
}

ensure_x11() {
  local x11_socket="$FEDORA_TERMUX_PREFIX/tmp/.X11-unix/X${FEDORA_DISPLAY#:}"
  local expected_x11_args="display=$FEDORA_DISPLAY legacy_drawing=$LEGACY_DRAWING force_bgra=$FORCE_BGRA"
  if [[ -L "$x11_pid_file" || ( -e "$x11_pid_file" && ! -f "$x11_pid_file" ) \
    || -L "$x11_args_file" || ( -e "$x11_args_file" && ! -f "$x11_args_file" ) ]]; then
    fedora_die "Refusing unsafe Termux:X11 state files; remove only the project-owned broken records after inspection"
    return 1
  fi
  if [[ -f "$x11_pid_file" ]]; then
    local old_pid
    old_pid="$(sed -n '1p' "$x11_pid_file" 2>/dev/null || true)"
    if fedora_pid_matches "$old_pid" termux-x11 \
      && [[ -S "$x11_socket" && ! -L "$x11_socket" ]]; then
      local recorded_x11_args=""
      if [[ -r "$x11_args_file" ]]; then
        recorded_x11_args="$(sed -n '1p' "$x11_args_file" 2>/dev/null || true)"
      fi
      # Old installations did not record launch flags. Reusing them is safe
      # for the ordinary path, but a requested compatibility flag must be
      # applied to a freshly-created X11 process or it would be a no-op.
      if [[ "$recorded_x11_args" == "$expected_x11_args" ]] \
        || { [[ -z "$recorded_x11_args" ]] && (( ! LEGACY_DRAWING && ! FORCE_BGRA )); }; then
        fedora_log "Reusing Termux:X11 process $old_pid on $FEDORA_DISPLAY."
        open_x11_activity
        return 0
      fi
      fedora_warn "Termux:X11 process $old_pid was started with different drawing flags; restarting the project-owned transport."
      fedora_kill_owned_pid "$x11_pid_file" termux-x11
      rm -f -- "$x11_args_file"
    fi
    if fedora_pid_matches "$old_pid" termux-x11; then
      fedora_warn "Recorded Termux:X11 process $old_pid has no socket $x11_socket; restarting the stale server."
      fedora_kill_owned_pid "$x11_pid_file" termux-x11
      rm -f -- "$x11_args_file"
    else
      rm -f -- "$x11_pid_file"
      rm -f -- "$x11_args_file"
    fi
  fi

  local -a x11_args=("$FEDORA_DISPLAY")
  (( LEGACY_DRAWING )) && x11_args+=(-legacy-drawing)
  (( FORCE_BGRA )) && x11_args+=(-force-bgra)
  fedora_log "Starting Termux:X11 display transport on $FEDORA_DISPLAY."
  TERMUX_X11_DEBUG="${TERMUX_X11_DEBUG:-0}" termux-x11 "${x11_args[@]}" \
    >> "$FEDORA_LOG_DIR/termux-x11.log" 2>&1 &
  local x11_pid=$!
  if ! fedora_atomic_write "$x11_pid_file" 600 <<< "$x11_pid" \
    || ! fedora_atomic_write "$x11_args_file" 600 <<< "$expected_x11_args"; then
    if fedora_pid_matches "$x11_pid" termux-x11; then
      kill "$x11_pid" 2>/dev/null || true
    fi
    rm -f -- "$x11_pid_file" "$x11_args_file"
    fedora_die "Could not record the project-owned Termux:X11 transport safely"
    return 1
  fi
  sleep 1
  open_x11_activity

  if fedora_is_true "$FEDORA_TERMUX_X11_FULLSCREEN"; then
    fedora_warn "Termux:X11 fullscreen is user-controlled and may hide Android bottom navigation; turn device fullscreen off for bottom-swipe Home/Back."
  else
    fedora_log "Safe navigation hint: leave Termux:X11 device fullscreen off for Android bottom-swipe/buttons. The preference is not changed automatically."
  fi
}

wait_for_x11_transport() {
  local x11_pid x11_socket tries=0
  x11_pid="$(sed -n '1p' "$x11_pid_file" 2>/dev/null || true)"
  x11_socket="$FEDORA_TERMUX_PREFIX/tmp/.X11-unix/X${FEDORA_DISPLAY#:}"
  # Android may delay activity/window creation while the tablet is resuming.
  # Give the transport 15 seconds before declaring a stale socket failure.
  while (( tries < 150 )); do
    if [[ -S "$x11_socket" && ! -L "$x11_socket" ]]; then
      return 0
    fi
    if ! fedora_pid_matches "$x11_pid" termux-x11; then
      fedora_die "Termux:X11 server exited before creating $x11_socket; inspect $FEDORA_LOG_DIR/termux-x11.log"
      return 1
    fi
    sleep 0.1
    ((tries += 1))
  done
  fedora_die "Termux:X11 socket is unavailable: $x11_socket. Install/open the compatible Termux:X11 APK, then retry."
}

verified_wayland_session() {
  local display_name session_type runtime_dir
  [[ -f "$session_state_host" && ! -L "$session_state_host" ]] || return 1
  display_name="$(sed -n 's/^WAYLAND_DISPLAY=//p' "$session_state_host" | sed -n '1p' || true)"
  session_type="$(sed -n 's/^XDG_SESSION_TYPE=//p' "$session_state_host" | sed -n '1p' || true)"
  [[ "$display_name" =~ ^wayland-[0-9]+$ && "$session_type" == wayland ]] || return 1
  runtime_dir="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime"
  [[ -d "$runtime_dir" && ! -L "$runtime_dir" ]] || return 1
  [[ -S "$runtime_dir/$display_name" && ! -L "$runtime_dir/$display_name" ]]
}

clear_android_bridge_queue() {
  local queue_dir="$1"
  [[ -d "$queue_dir" && ! -L "$queue_dir" ]] || return 0
  # The queue is project-owned, mode 0700, and contains only short-lived
  # requests/replies. Clearing it after a dead broker prevents a stale
  # user-clicked launch from being replayed on the next Linux session.
  find "$queue_dir" -maxdepth 1 \( -type f -o -type l \) \
    -name '*.*' -delete 2>/dev/null || true
}

android_app_bridge_enabled() {
  case "$FEDORA_ANDROID_APPS_MODE" in
    off|disabled|none|0|false|no) return 1 ;;
    on|enabled|1|true|yes|auto) return 0 ;;
    *) return 1 ;;
  esac
}

android_bridge_paths_safe() {
  local path
  for path in "$android_bridge_dir" "$android_bridge_dir/requests" "$android_bridge_dir/responses"; do
    fedora_path_is_safe "$path" || return 1
    [[ ! -L "$path" ]] || return 1
  done
}

ensure_android_bridge_broker() {
  if ! android_app_bridge_enabled; then
    fedora_log "Android application broker disabled (FEDORA_ANDROID_APPS_MODE=$FEDORA_ANDROID_APPS_MODE); no broker process will be started."
    # A tampered PID record must not turn an optional disabled feature into a
    # hard failure. fedora_kill_owned_pid still fails closed and never follows
    # an unsafe path; the caller merely continues without the broker.
    if ! fedora_kill_owned_pid "$android_bridge_pid_file" android-bridge-broker.sh; then
      fedora_warn "Could not clean the Android app broker PID record safely; leaving it untouched."
    fi
    clear_android_bridge_queue "$android_bridge_dir/requests"
    clear_android_bridge_queue "$android_bridge_dir/responses"
    return 0
  fi
  [[ -x "$android_bridge_script" && ! -L "$android_bridge_script" ]] || {
    fedora_warn "Android app broker is not installed; Fedora Android app entries will remain unavailable."
    return 0
  }
  if ! android_bridge_paths_safe; then
    fedora_warn "Android app broker runtime contains a symlink; refusing to use it and continuing without app entries."
    return 0
  fi
  if ! mkdir -p "$android_bridge_dir/requests" "$android_bridge_dir/responses"; then
    fedora_warn "Could not create the Android app broker runtime; continuing without app entries."
    return 0
  fi
  if ! android_bridge_paths_safe; then
    fedora_warn "Android app broker runtime changed to a symlink during setup; refusing to use it."
    return 0
  fi
  chmod 700 "$android_bridge_dir" "$android_bridge_dir/requests" "$android_bridge_dir/responses" 2>/dev/null || true

  if [[ -L "$android_bridge_pid_file" \
    || ( -e "$android_bridge_pid_file" && ! -f "$android_bridge_pid_file" ) ]]; then
    fedora_warn "Android app broker PID record is unsafe; continuing without the broker rather than following it"
    return 0
  fi
  if [[ -f "$android_bridge_pid_file" ]]; then
    local old_pid
    old_pid="$(sed -n '1p' "$android_bridge_pid_file" 2>/dev/null || true)"
    if fedora_pid_matches "$old_pid" android-bridge-broker.sh; then
      fedora_log "Reusing Android app broker process $old_pid."
      return 0
    fi
    rm -f -- "$android_bridge_pid_file"
    clear_android_bridge_queue "$android_bridge_dir/requests"
    clear_android_bridge_queue "$android_bridge_dir/responses"
  fi

  local parent_pid broker_pid
  parent_pid="$(sed -n '1p' "$x11_pid_file" 2>/dev/null || true)"
  [[ "$parent_pid" =~ ^[0-9]+$ ]] || parent_pid="$$"
  FEDORA_ANDROID_BRIDGE_DIR="$android_bridge_dir" \
    FEDORA_ANDROID_BRIDGE_POLL_INTERVAL="$FEDORA_ANDROID_BRIDGE_POLL_INTERVAL" \
  FEDORA_ANDROID_BRIDGE_LOG="$FEDORA_LOG_DIR/android-bridge-broker.log" \
    "$android_bridge_script" --serve "$parent_pid" \
    >> "$FEDORA_LOG_DIR/android-bridge-broker.log" 2>&1 &
  broker_pid="$!"
  if ! fedora_atomic_write "$android_bridge_pid_file" 600 <<< "$broker_pid"; then
    if fedora_pid_matches "$broker_pid" android-bridge-broker.sh; then
      kill "$broker_pid" 2>/dev/null || true
    fi
    rm -f -- "$android_bridge_pid_file"
    clear_android_bridge_queue "$android_bridge_dir/requests"
    clear_android_bridge_queue "$android_bridge_dir/responses"
    fedora_warn "Could not record the Android app broker safely; continuing without app entries."
    return 0
  fi
  sleep 0.2
  if fedora_pid_matches "$broker_pid" android-bridge-broker.sh; then
    fedora_log "Android app broker is ready (read-only enumeration and explicit foreground launches)."
  else
    fedora_warn "Android app broker exited during startup; Fedora desktop remains usable without Android app entries."
    rm -f -- "$android_bridge_pid_file"
    clear_android_bridge_queue "$android_bridge_dir/requests"
    clear_android_bridge_queue "$android_bridge_dir/responses"
  fi
}

ensure_virgl() {
  local mode="$FEDORA_GPU_MODE"
  if [[ -L "$virgl_pid_file" \
    || ( -e "$virgl_pid_file" && ! -f "$virgl_pid_file" ) ]]; then
    fedora_die "Refusing unsafe virgl PID record: $virgl_pid_file"
    return 1
  fi
  case "$mode" in
    auto|virpipe) ;;
    software|llvmpipe|softpipe|zink|none) return 0 ;;
    *) fedora_die "Unknown FEDORA_GPU_MODE=$mode"; return 1 ;;
  esac
  if [[ "$mode" == auto ]]; then
    rm -f -- "$virgl_pid_file"
    if fedora_have_cmd virgl_test_server_android; then
      fedora_log "virglrenderer-android is installed but auto mode keeps the stable software renderer; use FEDORA_GPU_MODE=virpipe for an explicit GPU experiment."
    else
      fedora_warn "virgl_test_server_android is absent; using Mesa llvmpipe software fallback for GNOME stability."
    fi
    return 0
  fi
  if ! fedora_have_cmd virgl_test_server_android; then
    rm -f -- "$virgl_pid_file"
    if [[ "$mode" == virpipe ]]; then
      fedora_die "FEDORA_GPU_MODE=virpipe requested, but virgl_test_server_android is not installed."
      return 1
    fi
    fedora_warn "virgl_test_server_android is absent; using Mesa llvmpipe software fallback for GNOME stability."
    return 0
  fi
  if [[ -f "$virgl_pid_file" ]]; then
    local old_pid
    old_pid="$(sed -n '1p' "$virgl_pid_file" 2>/dev/null || true)"
    if fedora_pid_matches "$old_pid" virgl_test_server_android; then
      fedora_log "Reusing virgl server process $old_pid."
      return 0
    fi
    rm -f -- "$virgl_pid_file"
  fi
  fedora_log "Starting virgl_test_server_android (experimental; renderer must be verified)."
  virgl_test_server_android \
    >> "$FEDORA_LOG_DIR/virgl.log" 2>&1 &
  local virgl_pid=$!
  if ! fedora_atomic_write "$virgl_pid_file" 600 <<< "$virgl_pid"; then
    if fedora_pid_matches "$virgl_pid" virgl_test_server_android; then
      kill "$virgl_pid" 2>/dev/null || true
    fi
    rm -f -- "$virgl_pid_file"
    fedora_die "Could not record the project-owned virgl process safely"
    return 1
  fi
  sleep 0.3
  if ! fedora_pid_matches "$virgl_pid" virgl_test_server_android; then
    fedora_die "virgl_test_server_android exited during startup; inspect $FEDORA_LOG_DIR/virgl.log"
    return 1
  fi
}

# shellcheck disable=SC2317
cleanup_transport() {
  if (( LEAVE_TRANSPORT )); then
    return 0
  fi
  fedora_kill_owned_pid "$android_bridge_pid_file" android-bridge-broker.sh || \
    fedora_warn "Android app broker cleanup was skipped because its PID record was unsafe."
  fedora_kill_owned_pid "$virgl_pid_file" virgl_test_server_android || \
    fedora_warn "virgl cleanup was skipped because its PID record was unsafe."
  fedora_kill_owned_pid "$x11_pid_file" termux-x11 || \
    fedora_warn "Termux:X11 cleanup was skipped because its PID record was unsafe."
  rm -f -- "$x11_args_file"
  if [[ -x "$FEDORA_INSTALL_ROOT/audio/stop.sh" ]]; then
    "$FEDORA_INSTALL_ROOT/audio/stop.sh" || true
  fi
  if (( marker_preflight_attempted )); then
    restore_guest_systemd_marker || true
  fi
}
trap cleanup_transport EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fedora_init_state
ensure_x11
fedora_log "Termux:X11 options: legacy_drawing=$LEGACY_DRAWING force_bgra=$FORCE_BGRA"
wait_for_x11_transport
fedora_log "Termux:X11 socket is ready; keep the companion Android Activity opened for a visible surface. For bottom-swipe navigation, keep its device fullscreen off."
fedora_log "Linux keyboard focus mode: ordinary hardware keys target the focused Termux:X11/Fedora surface; Android global keys remain SystemUI-owned."
if linux_mode_stop_requested; then
  fedora_log "Linux Mode stop was requested before Fedora startup; cleaning up project-owned transport."
  exit 0
fi
ensure_android_bridge_broker
ensure_virgl
if linux_mode_stop_requested; then
  fedora_log "Linux Mode stop was requested during display setup; Fedora startup is cancelled."
  exit 0
fi

if fedora_container_running; then
  if verified_wayland_session; then
    fedora_log "Fedora session is already running with a verified Wayland endpoint; reconnect completed."
    LEAVE_TRANSPORT=1
    exit 0
  fi
  # An active PRoot container without the exact current-session marker is not
  # proof of a visible desktop. Returning success here used to leave the user
  # with a black/old X11 surface and prevented the controller from reporting a
  # recoverable state. Do not start a second GNOME instance; ask the explicit
  # stop/recovery path to clean the project-owned Fedora process first.
  fedora_warn "Fedora container is active without a verified Wayland session; refusing to start a second GNOME session. Run scripts/stop.sh --yes, then retry."
  LEAVE_TRANSPORT=0
  exit 125
fi

marker_preflight_attempted=1
prepare_guest_systemd_marker
rm -f -- "$session_state_host"
if linux_mode_stop_requested; then
  fedora_log "Linux Mode stop was requested during startup; Fedora session will not be launched."
  exit 0
fi

if [[ -x "$FEDORA_INSTALL_ROOT/audio/start.sh" ]]; then
  case "$FEDORA_AUDIO_MODE" in
    off|disabled|none)
      fedora_log "Termux audio transport disabled (FEDORA_AUDIO_MODE=$FEDORA_AUDIO_MODE)."
      ;;
    auto)
      if [[ "$FEDORA_MEMORY_PROFILE" == low ]]; then
        fedora_log "Termux audio transport skipped by low memory profile; use FEDORA_AUDIO_MODE=on to enable it."
      else
        "$FEDORA_INSTALL_ROOT/audio/start.sh" || fedora_warn "Optional Termux audio transport did not start."
      fi
      ;;
    on|enabled)
      "$FEDORA_INSTALL_ROOT/audio/start.sh" || fedora_warn "Optional Termux audio transport did not start."
      ;;
    *)
      fedora_warn "Unknown FEDORA_AUDIO_MODE=$FEDORA_AUDIO_MODE; skipping optional Termux audio transport."
      ;;
  esac
fi

gpu_env=()
case "$FEDORA_GPU_MODE" in
  virpipe) gpu_env+=(GALLIUM_DRIVER=virpipe) ;;
  software|llvmpipe) gpu_env+=(GALLIUM_DRIVER=llvmpipe LIBGL_ALWAYS_SOFTWARE=1) ;;
  softpipe) gpu_env+=(GALLIUM_DRIVER=softpipe LIBGL_ALWAYS_SOFTWARE=1) ;;
  zink) gpu_env+=(GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink) ;;
  auto)
    # auto is deliberately deterministic: an installed experimental bridge
    # must never turn a known-good desktop into a black screen by surprise.
    gpu_env+=(GALLIUM_DRIVER=llvmpipe LIBGL_ALWAYS_SOFTWARE=1)
    ;;
  none) ;;
esac

session_env=(
  "DISPLAY=$FEDORA_DISPLAY"
  "XDG_RUNTIME_DIR=/tmp/fedora-runtime"
  "PIPEWIRE_RUNTIME_DIR=/tmp/fedora-runtime"
  "PIPEWIRE_REMOTE=pipewire-0"
  "PIPEWIRE_CORE=pipewire-0"
  "FEDORA_SESSION_RUNTIME=/tmp/fedora-runtime"
  "FEDORA_SESSION_LOG=/tmp/fedora-session.log"
  "FEDORA_GPU_MODE=$FEDORA_GPU_MODE"
  "FEDORA_AUDIO_MODE=$FEDORA_AUDIO_MODE"
  "FEDORA_MEMORY_PROFILE=$FEDORA_MEMORY_PROFILE"
  "FEDORA_ANDROID_APPS_MODE=$FEDORA_ANDROID_APPS_MODE"
  "FEDORA_ANDROID_APPS_SCOPE=$FEDORA_ANDROID_APPS_SCOPE"
  "FEDORA_KEYBOARD_MODE=$FEDORA_KEYBOARD_MODE"
  "FEDORA_ANDROID_BRIDGE_DIR=/tmp/fedora-runtime/android-bridge"
  "FEDORA_SETTINGS_DAEMON=$FEDORA_SETTINGS_DAEMON"
  "FEDORA_LAUNCH_TERMINAL=$FEDORA_LAUNCH_TERMINAL"
  "FEDORA_KEYRING_MODE=$FEDORA_KEYRING_MODE"
  "FEDORA_SEARCH_MODE=$FEDORA_SEARCH_MODE"
  "FEDORA_NESTED_SCALE=$FEDORA_NESTED_SCALE"
  "FEDORA_NESTED_MODE=$FEDORA_NESTED_MODE"
  "FEDORA_NESTED_XWAYLAND=$FEDORA_NESTED_XWAYLAND"
  "FEDORA_NESTED_MODE_SPECS=$FEDORA_NESTED_MODE_SPECS"
  "FEDORA_DEVKIT_GDK_BACKEND=$FEDORA_DEVKIT_GDK_BACKEND"
  "FEDORA_DEVKIT_PIPEWIRE=$FEDORA_DEVKIT_PIPEWIRE"
  "FEDORA_DEVKIT_PIPEWIRE_CONFIG=$FEDORA_DEVKIT_PIPEWIRE_CONFIG"
  "FEDORA_DEVKIT_DEBUG=$FEDORA_DEVKIT_DEBUG"
  "FEDORA_SYSTEM_BUS_MODE=$FEDORA_SYSTEM_BUS_MODE"
  "FEDORA_LINUX_MODE_STOP_REQUEST=${FEDORA_LINUX_MODE_STOP_REQUEST:-}"
  "FEDORA_ALLOW_X11=${FEDORA_ALLOW_X11:-0}"
  "FEDORA_SYSTEMD_MARKER_MASKED=$guest_systemd_marker_masked"
  "FEDORA_PORTAL_MODE=$FEDORA_PORTAL_MODE"
  "FEDORA_CALENDAR_MODE=$FEDORA_CALENDAR_MODE"
)
for item in "${gpu_env[@]}"; do
  session_env+=("$item")
done

fedora_init_state
if ! fedora_atomic_write "$FEDORA_STATE_DIR/session-host.env" 600 <<EOF
host_pid=$(printf '%q' "$$")
container=$(printf '%q' "$FEDORA_CONTAINER")
EOF
then
  fedora_die "Could not record Fedora session ownership safely"
  exit 1
fi

fedora_log "Launching Fedora GNOME session; Wayland is mandatory in auto/wayland modes."
set +e
fedora_pd_login /usr/bin/env "${session_env[@]}" /usr/local/bin/fedora-session
session_rc=$?
set -e

if [[ -f "$FEDORA_TERMUX_PREFIX/tmp/fedora-session.log" ]]; then
  if ! fedora_atomic_write "$FEDORA_LOG_DIR/fedora-session.log" 600 \
    < "$FEDORA_TERMUX_PREFIX/tmp/fedora-session.log"; then
    fedora_warn "Could not copy the guest Fedora session log safely"
  fi
fi
rm -f -- "$FEDORA_STATE_DIR/session-host.env"
exit "$session_rc"
