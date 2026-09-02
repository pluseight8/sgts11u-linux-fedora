#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Linux Mode controller v1. It owns only Fedora/Termux project processes.
# Android settings, packages, processes, kernel and memory policy remain
# untouched; choosing a Home app is always a user action in Android Settings.

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_init_state

MODE_STATE_DIR="${FEDORA_STATE_RECORD_DIR:-$FEDORA_STATE_DIR/state}"
MODE_STATE_FILE="$MODE_STATE_DIR/linux-mode-state.env"
MODE_LOCK_DIR="$FEDORA_STATE_DIR/linux-mode.lock"
MODE_RUNTIME_HOST_DIR="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime"
# --shared-tmp maps the Termux prefix tmp directory to /tmp inside PRoot. Keep
# the host and guest spellings separate: a host absolute path such as
# /data/data/.../.fedora-shell/state is not necessarily visible in the guest,
# while /tmp/fedora-runtime is. This makes a concurrent OFF request observable
# by fedora-session without exposing any Android path or changing Android.
MODE_STOP_REQUEST="$MODE_RUNTIME_HOST_DIR/linux-mode-stop.request"
MODE_GUEST_STOP_REQUEST="/tmp/fedora-runtime/linux-mode-stop.request"
MODE_SESSION_STATE_FILE="$MODE_RUNTIME_HOST_DIR/fedora-session-state.env"
MEMORY_GOVERNOR="$FEDORA_INSTALL_ROOT/integration/android-memory-governor.sh"
fedora_prepare_directories "$MODE_STATE_DIR" "$MODE_RUNTIME_HOST_DIR" || exit 1
chmod 700 "$MODE_STATE_DIR" 2>/dev/null || true
chmod 700 "$MODE_RUNTIME_HOST_DIR" 2>/dev/null || true

lock_acquired=0
release_lock() {
  (( lock_acquired )) || return 0
  if [[ -L "$MODE_LOCK_DIR" || ( -e "$MODE_LOCK_DIR" && ! -d "$MODE_LOCK_DIR" ) \
    || -L "$MODE_LOCK_DIR/owner" ]]; then
    fedora_warn "Linux Mode lock became unsafe; leaving it untouched for recovery."
    lock_acquired=0
    return 0
  fi
  local owner=""
  if [[ -r "$MODE_LOCK_DIR/owner" && -f "$MODE_LOCK_DIR/owner" ]]; then
    owner="$(sed -n '1p' "$MODE_LOCK_DIR/owner" 2>/dev/null || true)"
  fi
  if [[ "$owner" == "$$" ]]; then
    rm -f -- "$MODE_LOCK_DIR/owner"
    rmdir -- "$MODE_LOCK_DIR" 2>/dev/null || true
  fi
  lock_acquired=0
}

acquire_lock() {
  fedora_path_is_safe "$MODE_LOCK_DIR" || return 1
  if [[ -L "$MODE_LOCK_DIR" || ( -e "$MODE_LOCK_DIR" && ! -d "$MODE_LOCK_DIR" ) \
    || -L "$MODE_LOCK_DIR/owner" ]]; then
    fedora_die "Linux Mode lock path is unsafe; refusing the transition"
    return 1
  fi
  if mkdir -- "$MODE_LOCK_DIR" 2>/dev/null; then
    if [[ ! -d "$MODE_LOCK_DIR" || -L "$MODE_LOCK_DIR" \
      || -e "$MODE_LOCK_DIR/owner" || -L "$MODE_LOCK_DIR/owner" ]]; then
      rmdir -- "$MODE_LOCK_DIR" 2>/dev/null || true
      fedora_die "Linux Mode lock changed during creation; refusing the transition"
      return 1
    fi
    if ! fedora_atomic_write "$MODE_LOCK_DIR/owner" 600 <<< "$$"; then
      rm -f -- "$MODE_LOCK_DIR/owner"
      rmdir -- "$MODE_LOCK_DIR" 2>/dev/null || true
      fedora_die "Could not create a safe Linux Mode lock owner file"
      return 1
    fi
    lock_acquired=1
    return 0
  fi
  [[ -d "$MODE_LOCK_DIR" && ! -L "$MODE_LOCK_DIR" \
    && ( ! -e "$MODE_LOCK_DIR/owner" || -f "$MODE_LOCK_DIR/owner" ) \
    && ! -L "$MODE_LOCK_DIR/owner" ]] || {
    fedora_die "Linux Mode lock became unsafe while inspecting its owner"
    return 1
  }
  local owner=""
  owner="$(sed -n '1p' "$MODE_LOCK_DIR/owner" 2>/dev/null || true)"
  # A numeric PID can be recycled by Android/Termux. Treat the lock as live
  # only when it still belongs to this controller, rather than merely being
  # present in /proc.
  if [[ "$owner" =~ ^[0-9]+$ ]] && fedora_pid_matches "$owner" linux-mode.sh; then
    fedora_die "Linux Mode transition is already running (PID $owner)"
    return 1
  fi
  rm -f -- "$MODE_LOCK_DIR/owner"
  rmdir -- "$MODE_LOCK_DIR" 2>/dev/null || {
    fedora_die "Linux Mode lock is busy and its owner could not be verified"
    return 1
  }
  acquire_lock
}

controller_process_live() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  # Prefer command-line identity over a bare /proc existence check. Android can
  # recycle a PID while an interrupted state file is still present.
  fedora_pid_matches "$pid" linux-mode.sh
}

session_state_ready() {
  [[ -f "$MODE_SESSION_STATE_FILE" && ! -L "$MODE_SESSION_STATE_FILE" ]] || return 1
  grep -Eq '^WAYLAND_DISPLAY=wayland-[0-9]+$' "$MODE_SESSION_STATE_FILE" \
    && grep -Fxq 'XDG_SESSION_TYPE=wayland' "$MODE_SESSION_STATE_FILE"
}

wait_for_start_ready() {
  local start_pid="$1"
  local tries=0
  while (( tries < 600 )); do
    session_state_ready && return 0
    if ! fedora_has_pid "$start_pid"; then
      return 1
    fi
    # /proc/cmdline can be restricted on some Android builds. If it is
    # readable, verify that the child is still our start.sh; otherwise the
    # direct-child relationship remains the safe fallback.
    if [[ -r "/proc/$start_pid/cmdline" ]] \
      && ! fedora_pid_matches "$start_pid" start.sh; then
      return 1
    fi
    sleep 0.1
    ((tries += 1))
  done
  return 1
}

linux_mode_stop_requested() {
  [[ -f "$MODE_STOP_REQUEST" && ! -L "$MODE_STOP_REQUEST" ]]
}
trap release_lock EXIT
trap 'release_lock; exit 130' INT
trap 'release_lock; exit 143' TERM

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

atomic_state_write() {
  local mode="$1" phase="$2" profile="$3" clean_exit="$4" pid="$5"
  local started_utc="$6" exit_code="$7" last_error="${8:-}"
  local session_ready="${9:-false}"
  local temporary timestamp
  [[ -d "$MODE_STATE_DIR" && ! -L "$MODE_STATE_DIR" ]] || {
    fedora_die "Linux Mode state directory is unavailable or symlinked"
    return 1
  }
  if [[ -L "$MODE_STATE_FILE" || ( -e "$MODE_STATE_FILE" && ! -f "$MODE_STATE_FILE" ) ]]; then
    fedora_die "Linux Mode state file is unsafe: $MODE_STATE_FILE"
    return 1
  fi
  timestamp="$(utc_now)"
  temporary="$(mktemp "$MODE_STATE_DIR/.linux-mode-state.XXXXXX")" || return 1
  if ! {
    printf 'mode=%q\n' "$mode"
    printf 'phase=%q\n' "$phase"
    printf 'profile=%q\n' "$profile"
    printf 'clean_exit=%q\n' "$clean_exit"
    printf 'pid=%q\n' "$pid"
    printf 'started_utc=%q\n' "$started_utc"
    printf 'updated_utc=%q\n' "$timestamp"
    printf 'last_exit_code=%q\n' "$exit_code"
    printf 'last_error=%q\n' "$last_error"
    printf 'session_ready=%q\n' "$session_ready"
    printf 'keyboard_mode=%q\n' "${FEDORA_KEYBOARD_MODE:-linux}"
    printf 'android_changes_applied=false\n'
    printf 'home_selection=user-controlled-Android-Settings\n'
  } > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod 600 "$temporary" 2>/dev/null || true
  [[ ! -L "$MODE_STATE_FILE" ]] || {
    rm -f -- "$temporary"
    fedora_die "Linux Mode state file became a symlink during update"
    return 1
  }
  mv -f -- "$temporary" "$MODE_STATE_FILE"
  [[ -f "$MODE_STATE_FILE" && ! -L "$MODE_STATE_FILE" ]] || {
    fedora_die "Linux Mode state file failed its final safety check"
    return 1
  }
  chmod 600 "$MODE_STATE_FILE" 2>/dev/null || true
}

atomic_request_write() {
  local destination="$1"
  local value="$2"
  local parent temporary

  fedora_path_is_safe "$destination" || return 1
  if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
    fedora_die "Linux Mode request file is unsafe: $destination"
    return 1
  fi
  parent="${destination%/*}"
  [[ -n "$parent" ]] || parent="/"
  [[ -d "$parent" && ! -L "$parent" ]] || return 1
  temporary="$(mktemp "$parent/.linux-mode-request.XXXXXX")" || return 1
  if ! printf '%s\n' "$value" > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod 600 "$temporary" 2>/dev/null || true
  [[ ! -L "$destination" ]] || {
    rm -f -- "$temporary"
    fedora_die "Linux Mode request file became a symlink during update"
    return 1
  }
  mv -f -- "$temporary" "$destination"
  [[ -f "$destination" && ! -L "$destination" ]] || return 1
  chmod 600 "$destination" 2>/dev/null || true
}

state_value() {
  local key="$1"
  [[ -f "$MODE_STATE_FILE" && ! -L "$MODE_STATE_FILE" ]] || return 0
  sed -n "s/^${key}=//p" "$MODE_STATE_FILE" | sed -n '1p'
}

record_memory() {
  local label="$1"
  [[ -x "$MEMORY_GOVERNOR" ]] || return 0
  "$MEMORY_GOVERNOR" snapshot "$label" >/dev/null 2>&1 \
    || fedora_warn "Read-only memory snapshot '$label' was unavailable; Android was not changed."
}

record_no_change_receipt() {
  [[ -x "$MEMORY_GOVERNOR" ]] || return 0
  "$MEMORY_GOVERNOR" restore-evidence >/dev/null 2>&1 \
    || fedora_warn "Could not refresh the no-change Android policy receipt."
}

valid_profile() {
  case "$1" in
    balanced|linux-focused|maximum-linux) return 0 ;;
    *) return 1 ;;
  esac
}

profile_environment() {
  local profile="$1"
  PROFILE_ENV=()
  case "$profile" in
    balanced)
      PROFILE_ENV=(
        FEDORA_MEMORY_PROFILE=balanced FEDORA_GPU_MODE=auto FEDORA_AUDIO_MODE=auto
        FEDORA_ANDROID_APPS_MODE=on
        FEDORA_KEYBOARD_MODE=linux
        FEDORA_PORTAL_MODE=auto FEDORA_CALENDAR_MODE=auto FEDORA_NESTED_XWAYLAND=auto
        FEDORA_SETTINGS_DAEMON=auto FEDORA_LAUNCH_TERMINAL=auto FEDORA_KEYRING_MODE=auto
        FEDORA_SEARCH_MODE=auto FEDORA_NESTED_MODE_SPECS=
        FEDORA_DEVKIT_GDK_BACKEND=x11 FEDORA_DEVKIT_PIPEWIRE=auto
        FEDORA_LINUX_MODE_STOP_REQUEST=$MODE_GUEST_STOP_REQUEST
        FEDORA_LINUX_MODE_STOP_REQUEST_HOST=$MODE_STOP_REQUEST
      )
      ;;
    linux-focused)
      PROFILE_ENV=(
        FEDORA_MEMORY_PROFILE=low FEDORA_GPU_MODE=software FEDORA_AUDIO_MODE=off
        FEDORA_ANDROID_APPS_MODE=on
        FEDORA_KEYBOARD_MODE=linux
        FEDORA_PORTAL_MODE=off FEDORA_CALENDAR_MODE=off FEDORA_NESTED_XWAYLAND=off
        FEDORA_SETTINGS_DAEMON=off FEDORA_LAUNCH_TERMINAL=off FEDORA_KEYRING_MODE=off
        FEDORA_SEARCH_MODE=off FEDORA_NESTED_MODE_SPECS=1920x1200
        FEDORA_DEVKIT_GDK_BACKEND=x11 FEDORA_DEVKIT_PIPEWIRE=on
        FEDORA_LINUX_MODE_STOP_REQUEST=$MODE_GUEST_STOP_REQUEST
        FEDORA_LINUX_MODE_STOP_REQUEST_HOST=$MODE_STOP_REQUEST
        FEDORA_TERMUX_X11_LEGACY_DRAWING=1
      )
      ;;
    maximum-linux)
      PROFILE_ENV=(
        FEDORA_MEMORY_PROFILE=low FEDORA_GPU_MODE=software FEDORA_AUDIO_MODE=off
        FEDORA_ANDROID_APPS_MODE=on
        FEDORA_KEYBOARD_MODE=linux
        FEDORA_PORTAL_MODE=off FEDORA_CALENDAR_MODE=off FEDORA_NESTED_XWAYLAND=off
        FEDORA_SETTINGS_DAEMON=off FEDORA_LAUNCH_TERMINAL=off FEDORA_KEYRING_MODE=off
        # Explicit opt-in profile: reduce Fedora-side allocator fragmentation
        # and nested compositor buffers further. This does not change the
        # Android panel, Android RAM Plus, zRAM, LMKD or kernel policy.
        FEDORA_SEARCH_MODE=off FEDORA_NESTED_MODE_SPECS=1600x1000
        MALLOC_ARENA_MAX=1 MALLOC_TRIM_THRESHOLD_=65536
        FEDORA_DEVKIT_GDK_BACKEND=x11 FEDORA_DEVKIT_PIPEWIRE=on
        FEDORA_LINUX_MODE_STOP_REQUEST=$MODE_GUEST_STOP_REQUEST
        FEDORA_LINUX_MODE_STOP_REQUEST_HOST=$MODE_STOP_REQUEST
        FEDORA_TERMUX_X11_LEGACY_DRAWING=1
      )
      ;;
    *) fedora_die "Unknown Linux Mode profile: $profile"; return 64 ;;
  esac
}

profile_label() {
  case "$1" in
    balanced) printf '%s\n' 'Balanced' ;;
    linux-focused) printf '%s\n' 'Linux Focused (Fedora-side)' ;;
    maximum-linux) printf '%s\n' 'Maximum Linux (Fedora-side only)' ;;
  esac
}

container_active() { fedora_container_running; }

enable_linux_mode() {
  local profile="${1:-$FEDORA_LINUX_MODE_PROFILE}"
  valid_profile "$profile" || { fedora_die "Profile must be balanced, linux-focused or maximum-linux"; return 64; }
  fedora_require_container || return 1

  local current_phase current_mode current_pid started_utc start_rc=0 final_rc=0
  local start_pid session_ready=0
  local start_attempt=0 max_start_attempts=2
  acquire_lock

  # Re-read all state only after taking the lock. The first check must not be
  # trusted: two HOME/GUI taps can arrive in the same scheduling window.
  current_phase="$(state_value phase || true)"
  current_mode="$(state_value mode || true)"
  current_pid="$(state_value pid || true)"
  if [[ "$current_phase" == stopping ]] \
    && controller_process_live "$current_pid"; then
    release_lock
    fedora_die "Linux Mode is stopping (PID $current_pid); wait for it to finish and retry"
    return 1
  fi
  if [[ "$current_phase" == starting || "$current_phase" == running ]] \
    && controller_process_live "$current_pid"; then
    release_lock
    fedora_log "Linux Mode is already active or starting (PID $current_pid)."
    record_no_change_receipt
    return 0
  fi
  if container_active; then
    started_utc="$(state_value started_utc || true)"
    if session_state_ready; then
      atomic_state_write linux running "$profile" 0 "$$" "${started_utc:-$(utc_now)}" 0 "" true
      release_lock
      fedora_log "Fedora is already running with a verified Wayland session; refusing to start a second Linux session."
      record_no_change_receipt
      return 0
    fi
    atomic_state_write linux needs-recovery "$profile" 0 "$$" "${started_utc:-$(utc_now)}" 125 \
      "Fedora container is active without a verified Wayland session" false
    release_lock
    record_no_change_receipt
    fedora_warn "Fedora container is active without a verified Wayland session; use 'linux-mode.sh recover' before retrying. No second session was started."
    return 125
  fi

  rm -f -- "$MODE_STOP_REQUEST"
  rm -f -- "$MODE_SESSION_STATE_FILE"
  # Do not let a previous successful run be mistaken for this transition's
  # post-start measurement. The after snapshot is recreated only after the
  # current attempt publishes a verified Wayland session marker.
  rm -f -- "$MODE_STATE_DIR/memory-after.json"
  started_utc="$(utc_now)"
  atomic_state_write linux starting "$profile" 0 "$$" "$started_utc" 0 ""
  record_memory before
  profile_environment "$profile"
  atomic_state_write linux running "$profile" 0 "$$" "$started_utc" 0 ""
  release_lock

  fedora_log "Linux Mode ON: $(profile_label "$profile"). Android policy remains read-only and unchanged."
  while (( start_attempt < max_start_attempts )); do
    ((start_attempt += 1))
    session_ready=0
    rm -f -- "$MODE_STATE_DIR/memory-after.json"
    if (( start_attempt > 1 )); then
      # The previous start.sh has returned and its EXIT trap has already
      # cleaned only project-owned Fedora resources. Mark the retry as not yet
      # ready so a Home/status probe cannot mistake a stale Wayland socket for
      # a usable desktop.
      acquire_lock
      current_mode="$(state_value mode || true)"
      current_phase="$(state_value phase || true)"
      current_pid="$(state_value pid || true)"
      if [[ "$current_mode" == linux && "$current_phase" == running \
        && "$current_pid" == "$$" ]]; then
        atomic_state_write linux running "$profile" 0 "$$" "$started_utc" 0 "" false
      fi
      release_lock
      linux_mode_stop_requested && break
      fedora_warn "Fedora session ended unexpectedly; retrying once after owned-resource cleanup ($start_attempt/$max_start_attempts)."
      sleep 1
    fi

    set +e
    env "${PROFILE_ENV[@]}" FEDORA_LINUX_MODE=1 \
      bash "$FEDORA_INSTALL_ROOT/scripts/start.sh" --legacy-drawing &
    start_pid=$!
    if wait_for_start_ready "$start_pid"; then
      session_ready=1
      # A simultaneous OFF may have moved the state to stopping. Never replace
      # that transition with a misleading running/ready record.
      acquire_lock
      current_mode="$(state_value mode || true)"
      current_phase="$(state_value phase || true)"
      current_pid="$(state_value pid || true)"
      if [[ "$current_mode" == linux && "$current_phase" == running \
        && "$current_pid" == "$$" ]]; then
        atomic_state_write linux running "$profile" 0 "$$" "$started_utc" 0 "" true
      fi
      release_lock
      # Allow GNOME helpers started immediately after the viewer to settle so
      # the after snapshot describes the usable foreground session, not just
      # Mutter's first Wayland socket.
      sleep 1
      record_memory after
    fi
    # The readiness probe is advisory. The child exit code remains the source
    # of truth for crash/recovery state; a successful session that was stopped
    # before the marker became visible must not inherit the probe's boolean
    # status.
    start_rc=0
    wait "$start_pid" || start_rc=$?
    set -e
    record_memory now

    # A clean stop request is never retried. A session that actually published
    # its ready marker and then ended cleanly is also not retried. A zero exit
    # without readiness (for example, a stale-container reconnect) is not a
    # usable desktop and gets the same single bounded recovery attempt as a
    # non-zero Fedora/Devkit exit.
    if { (( start_rc == 0 && session_ready == 1 )); } \
      || linux_mode_stop_requested; then
      break
    fi
  done

  acquire_lock
  current_mode="$(state_value mode || true)"
  current_phase="$(state_value phase || true)"
  if [[ -e "$MODE_STOP_REQUEST" ]] \
    || { [[ "$current_mode" == android ]] \
      && [[ "$current_phase" == stopping || "$current_phase" == stopped ]]; }; then
    # OFF may race with the short interval between start.sh's checks. Make a
    # second idempotent cleanup pass if the guest became running after the first
    # stop.sh invocation; only project-owned resources are touched.
    release_lock
    if container_active || [[ -f "$FEDORA_PID_DIR/termux-x11.pid" ]]; then
      bash "$FEDORA_INSTALL_ROOT/scripts/stop.sh" --yes || fedora_warn "Raced Fedora cleanup was incomplete; retry recover."
    fi
    acquire_lock
    rm -f -- "$MODE_STOP_REQUEST"
    atomic_state_write android stopped "$profile" 1 "$$" "$started_utc" "$start_rc" "" false
    release_lock
    fedora_log "Linux Mode stopped by request; Android/One UI were not modified."
    return 0
  fi
  if (( start_rc == 0 && session_ready == 1 )); then
    atomic_state_write linux exited "$profile" 0 "$$" "$started_utc" "$start_rc" "Session ended without an explicit stop request" false
  else
    final_rc="$start_rc"
    (( final_rc == 0 )) && final_rc=125
    atomic_state_write linux crashed "$profile" 0 "$$" "$started_utc" "$start_rc" "Fedora did not leave a usable ready session" false
  fi
  release_lock
  record_no_change_receipt
  fedora_warn "Linux Mode ended without a stop request; use 'linux-mode.sh recover'."
  return "$final_rc"
}

disable_linux_mode() {
  local profile stop_rc=0 started_utc current_phase current_pid
  acquire_lock
  # Read the recorded profile only after locking. An ON request may be writing
  # its initial state at the same time as the user presses OFF; using a stale
  # pre-lock value would make the final receipt misleading.
  profile="$(state_value profile || true)"
  valid_profile "$profile" || profile="$FEDORA_LINUX_MODE_PROFILE"
  started_utc="$(state_value started_utc || true)"
  current_phase="$(state_value phase || true)"
  current_pid="$(state_value pid || true)"
  if [[ "$current_phase" == stopping ]] \
    && controller_process_live "$current_pid"; then
    release_lock
    fedora_die "Linux Mode is already stopping (PID $current_pid); wait for it to finish"
    return 1
  fi
  atomic_request_write "$MODE_STOP_REQUEST" "$(utc_now)" || {
    release_lock
    fedora_die "Could not create a safe Linux Mode stop request"
    return 1
  }
  atomic_state_write android stopping "$profile" 0 "$$" "${started_utc:-$(utc_now)}" 0 ""
  record_no_change_receipt
  # Do not hold the transition lock while stop.sh waits for PRoot and the
  # transport to exit: the foreground enable invocation must be able to see
  # this stop request and finish its own state record.
  release_lock
  fedora_log "Linux Mode OFF: stopping only Fedora and project-owned transport."
  if [[ -x "$FEDORA_INSTALL_ROOT/scripts/stop.sh" ]]; then
    bash "$FEDORA_INSTALL_ROOT/scripts/stop.sh" --yes || stop_rc=$?
  else
    fedora_warn "Installed stop.sh is missing: $FEDORA_INSTALL_ROOT/scripts/stop.sh"
    stop_rc=1
  fi
  # Keep memory-after.json as the post-start snapshot of a usable Linux Mode.
  # The OFF path is a separate observation and must not overwrite that
  # before/after comparison with a post-shutdown value.
  record_memory now
  acquire_lock
  rm -f -- "$MODE_STOP_REQUEST"
  if (( stop_rc == 0 )); then
    atomic_state_write android stopped "$profile" 1 "$$" "${started_utc:-$(utc_now)}" 0 "" false
    fedora_log "Android Mode restored. No Android setting or package policy was changed."
  else
    atomic_state_write android needs-recovery "$profile" 0 "$$" "${started_utc:-$(utc_now)}" "$stop_rc" "Fedora transport did not stop cleanly" false
    fedora_warn "Fedora stop was incomplete; Android still was not modified. Retry linux-mode.sh disable."
  fi
  release_lock
  return "$stop_rc"
}

print_status() {
  local mode phase profile clean_exit pid updated session_ready keyboard_mode running=0
  mode="$(state_value mode || true)"; phase="$(state_value phase || true)"
  profile="$(state_value profile || true)"; clean_exit="$(state_value clean_exit || true)"
  pid="$(state_value pid || true)"; updated="$(state_value updated_utc || true)"
  session_ready="$(state_value session_ready || true)"
  keyboard_mode="$(state_value keyboard_mode || true)"
  container_active && running=1 || true
  printf 'Linux Mode state: mode=%s phase=%s profile=%s clean_exit=%s session_ready=%s pid=%s updated=%s\n' \
    "${mode:-unknown}" "${phase:-unknown}" "${profile:-unknown}" "${clean_exit:-unknown}" \
    "${session_ready:-unknown}" "${pid:-unknown}" "${updated:-unknown}"
  if (( running )); then printf '%s\n' 'Fedora container: running'; else printf '%s\n' 'Fedora container: stopped or not observable'; fi
  printf '%s\n' 'Android/One UI: unchanged; Home selection remains user-controlled in Android Settings'
  printf 'Keyboard: %s; ordinary keys require focused Termux:X11/Fedora surface; Android global keys remain protected\n' \
    "${keyboard_mode:-${FEDORA_KEYBOARD_MODE:-linux}}"
  printf 'Android policy receipt: %s\n' "$MODE_STATE_DIR/android-policy-backup.json"
  if [[ "$phase" == crashed || "$phase" == exited || "$phase" == needs-recovery ]]; then
    printf 'Recovery: %s/scripts/linux-mode.sh recover\n' "$FEDORA_INSTALL_ROOT"
  fi
}

print_setup_status() {
  local socket="$FEDORA_TERMUX_PREFIX/tmp/.X11-unix/X${FEDORA_DISPLAY#:}"
  local termux_state=not-observed x11_state=not-observed package_check_rc
  if [[ -x /system/bin/pm || -x /system/bin/cmd ]]; then
    if fedora_android_package_installed com.termux; then
      termux_state=installed
    else
      package_check_rc=$?
      [[ "$package_check_rc" == 1 ]] && termux_state=not-found || termux_state=not-confirmed
    fi
    if fedora_android_package_installed com.termux.x11; then
      x11_state=installed
    else
      package_check_rc=$?
      [[ "$package_check_rc" == 1 ]] && x11_state=not-found || x11_state=not-confirmed
    fi
  fi
  printf 'GUI setup prerequisites (read-only): Termux=%s Termux:X11=%s\n' "$termux_state" "$x11_state"
  [[ -S "$socket" ]] && printf 'Termux:X11 socket: ready (%s)\n' "$socket" || printf 'Termux:X11 socket: not ready (%s)\n' "$socket"
  printf 'Keyboard focus: %s (read-only; tap the Fedora/Termux:X11 surface)\n' \
    "${FEDORA_KEYBOARD_MODE:-linux}"
  printf '%s\n' 'Android Home/Back/volume/notification and other protected global keys remain Android-owned.'
  if fedora_container_exists; then printf 'Fedora container: installed (%s)\n' "$FEDORA_CONTAINER"; else printf 'Fedora container: not installed (%s)\n' "$FEDORA_CONTAINER"; fi
  printf '%s\n' 'Fedora Shell cannot silently become Home; select it in Android Home settings.'
}

usage() {
  cat >&2 <<'EOF'
Usage: linux-mode.sh COMMAND [OPTIONS]

Commands:
  setup-status                         read-only first-run prerequisites
  status                               show Linux/Android mode state
  enable [--profile PROFILE]          start Fedora Linux Mode
  disable                              stop Fedora and return to Android Mode
  toggle [--profile PROFILE]          enable or disable based on current state
  memory                               capture and print read-only memory data
  recover                              stop an unclean Fedora session safely

Profiles: balanced, linux-focused, maximum-linux
EOF
}

command_name="${1:-status}"
shift || true
profile_arg=""
while (( $# > 0 )); do
  case "$1" in
    --profile)
      (( $# >= 2 )) || { usage; exit 64; }
      profile_arg="$2"
      shift 2
      ;;
    --profile=*)
      profile_arg="${1#*=}"
      shift
      ;;
    -h|--help|help)
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

case "$command_name" in
  setup-status)
    print_setup_status
    ;;
  status)
    record_no_change_receipt
    print_status
    ;;
  enable)
    enable_linux_mode "${profile_arg:-$FEDORA_LINUX_MODE_PROFILE}"
    ;;
  disable)
    disable_linux_mode
    ;;
  toggle)
    phase="$(state_value phase || true)"
    if [[ "$phase" == stopping ]]; then
      disable_linux_mode
    elif [[ "$phase" == starting || "$phase" == running ]] || container_active; then
      disable_linux_mode
    else
      enable_linux_mode "${profile_arg:-$FEDORA_LINUX_MODE_PROFILE}"
    fi
    ;;
  memory)
    [[ -x "$MEMORY_GOVERNOR" ]] || {
      fedora_die "Read-only memory monitor is missing: $MEMORY_GOVERNOR"
      exit 1
    }
    exec "$MEMORY_GOVERNOR" memory
    ;;
  recover)
    phase="$(state_value phase || true)"
    if [[ "$phase" == crashed || "$phase" == exited || "$phase" == needs-recovery ]] || container_active; then
      disable_linux_mode
    else
      record_no_change_receipt
      fedora_log "No unclean Fedora session was detected; Android was not changed."
    fi
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    fedora_die "Unknown command: $command_name"
    exit 64
    ;;
esac
