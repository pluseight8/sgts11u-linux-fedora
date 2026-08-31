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
if [[ -x /system/bin/pm ]] && ! fedora_android_package_installed com.termux.x11; then
  fedora_die "Termux:X11 Android APK (com.termux.x11) is not installed. Install the compatible APK from the same source as Termux, open it once, then retry."
  exit 1
fi

if [[ ! "$FEDORA_DISPLAY" =~ ^:[0-9]+$ ]]; then
  fedora_die "FEDORA_DISPLAY must look like :0 or :1; got '$FEDORA_DISPLAY'"
  exit 64
fi

x11_pid_file="$FEDORA_PID_DIR/termux-x11.pid"
x11_args_file="$FEDORA_PID_DIR/termux-x11.args"
virgl_pid_file="$FEDORA_PID_DIR/virgl.pid"
session_state_host="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/fedora-session-state.env"

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
  if [[ -f "$x11_pid_file" ]]; then
    local old_pid
    old_pid="$(sed -n '1p' "$x11_pid_file" 2>/dev/null || true)"
    if fedora_pid_matches "$old_pid" termux-x11 && [[ -S "$x11_socket" ]]; then
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
  printf '%s\n' "$x11_pid" > "$x11_pid_file"
  printf '%s\n' "$expected_x11_args" > "$x11_args_file"
  chmod 600 "$x11_pid_file"
  chmod 600 "$x11_args_file"
  sleep 1
  open_x11_activity

  if fedora_is_true "$FEDORA_TERMUX_X11_FULLSCREEN" && fedora_have_cmd termux-x11-preference; then
    if fedora_have_cmd timeout; then
      timeout 3 termux-x11-preference fullscreen=true \
        >> "$FEDORA_LOG_FILE" 2>&1 || fedora_warn "Termux:X11 fullscreen preference was not applied."
    else
      termux-x11-preference fullscreen=true \
        >> "$FEDORA_LOG_FILE" 2>&1 || fedora_warn "Termux:X11 fullscreen preference was not applied."
    fi
  fi
}

wait_for_x11_transport() {
  local x11_pid x11_socket tries=0
  x11_pid="$(sed -n '1p' "$x11_pid_file" 2>/dev/null || true)"
  x11_socket="$FEDORA_TERMUX_PREFIX/tmp/.X11-unix/X${FEDORA_DISPLAY#:}"
  # Android may delay activity/window creation while the tablet is resuming.
  # Give the transport 15 seconds before declaring a stale socket failure.
  while (( tries < 150 )); do
    if [[ -S "$x11_socket" ]]; then
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

ensure_virgl() {
  local mode="$FEDORA_GPU_MODE"
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
  printf '%s\n' "$virgl_pid" > "$virgl_pid_file"
  chmod 600 "$virgl_pid_file"
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
  fedora_kill_owned_pid "$virgl_pid_file" virgl_test_server_android
  fedora_kill_owned_pid "$x11_pid_file" termux-x11
  rm -f -- "$x11_args_file"
  if [[ -x "$FEDORA_INSTALL_ROOT/audio/stop.sh" ]]; then
    "$FEDORA_INSTALL_ROOT/audio/stop.sh" || true
  fi
  local am_bin=""
  [[ -x /system/bin/am ]] && am_bin=/system/bin/am
  if [[ -n "$am_bin" ]]; then
    "$am_bin" broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 \
      >> "$FEDORA_LOG_FILE" 2>&1 || true
  fi
}
trap cleanup_transport EXIT INT TERM

fedora_init_state
ensure_x11
fedora_log "Termux:X11 options: legacy_drawing=$LEGACY_DRAWING force_bgra=$FORCE_BGRA"
wait_for_x11_transport
fedora_log "Termux:X11 socket is ready; keep the companion Android Activity opened for a visible surface."
ensure_virgl

if fedora_container_running; then
  fedora_log "Fedora session is already running; reconnect completed."
  LEAVE_TRANSPORT=1
  exit 0
fi

rm -f -- "$session_state_host"

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
  "FEDORA_SESSION_RUNTIME=/tmp/fedora-runtime"
  "FEDORA_SESSION_LOG=/tmp/fedora-session.log"
  "FEDORA_GPU_MODE=$FEDORA_GPU_MODE"
  "FEDORA_AUDIO_MODE=$FEDORA_AUDIO_MODE"
  "FEDORA_MEMORY_PROFILE=$FEDORA_MEMORY_PROFILE"
  "FEDORA_SETTINGS_DAEMON=$FEDORA_SETTINGS_DAEMON"
  "FEDORA_LAUNCH_TERMINAL=$FEDORA_LAUNCH_TERMINAL"
  "FEDORA_KEYRING_MODE=$FEDORA_KEYRING_MODE"
  "FEDORA_SEARCH_MODE=$FEDORA_SEARCH_MODE"
  "FEDORA_NESTED_SCALE=$FEDORA_NESTED_SCALE"
  "FEDORA_NESTED_MODE=$FEDORA_NESTED_MODE"
  "FEDORA_NESTED_MODE_SPECS=$FEDORA_NESTED_MODE_SPECS"
  "FEDORA_DEVKIT_GDK_BACKEND=$FEDORA_DEVKIT_GDK_BACKEND"
  "FEDORA_DEVKIT_PIPEWIRE=$FEDORA_DEVKIT_PIPEWIRE"
  "FEDORA_ALLOW_X11=${FEDORA_ALLOW_X11:-0}"
  "FEDORA_PORTAL_MODE=$FEDORA_PORTAL_MODE"
)
for item in "${gpu_env[@]}"; do
  session_env+=("$item")
done

fedora_init_state
printf 'host_pid=%q\n' "$$" > "$FEDORA_STATE_DIR/session-host.env"
printf 'container=%q\n' "$FEDORA_CONTAINER" >> "$FEDORA_STATE_DIR/session-host.env"
chmod 600 "$FEDORA_STATE_DIR/session-host.env"

fedora_log "Launching Fedora GNOME session; Wayland is mandatory in auto/wayland modes."
set +e
fedora_pd_login /usr/bin/env "${session_env[@]}" /usr/local/bin/fedora-session
session_rc=$?
set -e

if [[ -f "$FEDORA_TERMUX_PREFIX/tmp/fedora-session.log" ]]; then
  cp -- "$FEDORA_TERMUX_PREFIX/tmp/fedora-session.log" "$FEDORA_LOG_DIR/fedora-session.log"
  chmod 600 "$FEDORA_LOG_DIR/fedora-session.log"
fi
rm -f -- "$FEDORA_STATE_DIR/session-host.env"
exit "$session_rc"
