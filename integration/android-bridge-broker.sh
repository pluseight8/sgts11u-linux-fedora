#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-android-bridge-broker-v1
#
# This is a very small, local, file-based broker. It runs in the ordinary
# Termux UID, not in Fedora/PRoot, because a PRoot guest is not required to
# expose Android's /system/bin/am or /system/bin/pm. The guest can therefore
# request only the two operations below through shared-tmp:
#
#   * enumerate launchable third-party Android packages (read-only)
#   * start one exact, user-selected Android package/activity
#
# It is deliberately not a general shell/RPC bridge. Request fields are
# parsed and validated; no request is sourced as shell code. Android policy,
# settings, package state and process state are never changed here.

BROKER_DIR="${FEDORA_ANDROID_BRIDGE_DIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp/fedora-runtime/android-bridge}"
BROKER_LOG="${FEDORA_ANDROID_BRIDGE_LOG:-/dev/null}"
PARENT_PID=""
REQUEST_DIR="$BROKER_DIR/requests"
RESPONSE_DIR="$BROKER_DIR/responses"
MAX_PAYLOAD_BYTES=65536
BROKER_POLL_INTERVAL="${FEDORA_ANDROID_BRIDGE_POLL_INTERVAL:-0.25}"

if [[ ! "$BROKER_POLL_INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] \
  || ! awk -v interval="$BROKER_POLL_INTERVAL" \
    'BEGIN { exit !(interval >= 0.05 && interval <= 5) }'; then
  BROKER_POLL_INTERVAL=0.25
fi

usage() {
  cat >&2 <<'EOF'
Usage: android-bridge-broker.sh --serve PARENT_PID

The broker is normally started by Fedora Shell's start.sh. It accepts only
read-only app enumeration and explicit user-triggered Android activity starts.
EOF
}

log() {
  printf '[fedora-android-broker] %s\n' "$*" >> "$BROKER_LOG" 2>/dev/null || true
}

valid_package_name() {
  [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]]
}

valid_intent_action() {
  [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$ ]]
}

broker_paths_safe() {
  local broker_path
  for broker_path in "$BROKER_DIR" "$REQUEST_DIR" "$RESPONSE_DIR"; do
    case "$broker_path" in
      /*) ;;
      *) return 1 ;;
    esac
    case "$broker_path" in
      */../*|*/..|*/./*|*/.) return 1 ;;
    esac
    [[ -d "$broker_path" && ! -L "$broker_path" ]] || return 1
    local current="${broker_path%/*}"
    [[ -n "$current" ]] || current=/
    while [[ "$current" != / ]]; do
      [[ ! -L "$current" && ( ! -e "$current" || -d "$current" ) ]] || return 1
      current="${current%/*}"
      [[ -n "$current" ]] || current=/
    done
  done
}

android_bin() {
  local name="$1"
  if [[ -x "/system/bin/$name" ]]; then
    printf '%s\n' "/system/bin/$name"
  elif command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
  else
    return 1
  fi
}

package_output_is_valid() {
  local output="${1:-}"
  [[ -z "$output" ]] || awk '
    NF && $0 !~ /^package:[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/ { invalid = 1 }
    END { exit invalid }
  ' <<< "$output"
}

package_list_command() {
  local command_path="$1"
  shift
  local output=""
  output="$("$command_path" "$@" 2>/dev/null)" || return 1
  package_output_is_valid "$output" || return 1
  [[ -z "$output" ]] || printf '%s\n' "$output"
}

package_list() {
  local scope="${1:-user}"
  local pm_bin=""
  local cmd_bin=""
  if pm_bin="$(android_bin pm 2>/dev/null)"; then
    if [[ "$scope" == all ]]; then
      if package_list_command "$pm_bin" list packages; then
        return 0
      fi
    else
      if package_list_command "$pm_bin" list packages -3; then
        return 0
      fi
    fi
  fi
  if cmd_bin="$(android_bin cmd 2>/dev/null)"; then
    if [[ "$scope" == all ]]; then
      if package_list_command "$cmd_bin" package list packages; then
        return 0
      fi
    else
      if package_list_command "$cmd_bin" package list packages -3; then
        return 0
      fi
    fi
  fi
  return 1
}

query_launchable_components() {
  local cmd_bin=""
  if ! cmd_bin="$(android_bin cmd 2>/dev/null)"; then
    return 1
  fi
  # `query-activities` is read-only. Android releases differ slightly in the
  # accepted option order, so an unsupported form simply activates the safe
  # package-list fallback in list_apps().
  "$cmd_bin" package query-activities --brief --components --user 0 \
    -a android.intent.action.MAIN \
    -c android.intent.category.LAUNCHER 2>/dev/null
}

list_apps() {
  local scope="${1:-user}"
  [[ "$scope" == user || "$scope" == all ]] || return 64

  local packages=""
  local package_list_available=0
  if packages="$(package_list "$scope" 2>/dev/null)"; then
    package_list_available=1
  else
    # `query-activities` is itself a read-only resolver. On some Android 16
    # vendor builds it remains available when package enumeration is denied.
    # Only `all` may use that resolver-only path; `user` stays constrained by
    # the explicit third-party package inventory.
    [[ "$scope" == all ]] || return $?
  fi
  declare -A allowed_packages=()
  local line package_name
  while IFS= read -r line; do
    package_name="${line#package:}"
    valid_package_name "$package_name" || continue
    allowed_packages["$package_name"]=1
  done <<< "$packages"

  local query=""
  query="$(query_launchable_components 2>/dev/null || true)"
  declare -A seen=()
  local component candidate activity
  if [[ -n "$query" ]]; then
    while IFS= read -r line; do
      # The platform command normally prints one component per line, but some
      # builds indent it or prefix diagnostic words. Keep only the final token.
      candidate="${line##* }"
      [[ "$candidate" == */* ]] || continue
      package_name="${candidate%%/*}"
      activity="${candidate#*/}"
      valid_package_name "$package_name" || continue
      [[ "$activity" =~ ^[a-zA-Z0-9_.$]+$ ]] || continue
      if [[ "$scope" == all || -n "${allowed_packages[$package_name]:-}" ]]; then
        [[ -n "${seen[$package_name]:-}" ]] && continue
        seen["$package_name"]=1
        printf '%s|%s\n' "$package_name" "$candidate"
      fi
    done <<< "$query"
  fi

  # If query-activities is unavailable/restricted, return exact package IDs as
  # a transparent fallback. The launcher still asks Android's MAIN/LAUNCHER
  # resolver at click time; no package is installed or changed.
  if (( ${#seen[@]} == 0 && package_list_available )); then
    while IFS= read -r line; do
      package_name="${line#package:}"
      valid_package_name "$package_name" || continue
      [[ -n "${seen[$package_name]:-}" ]] && continue
      seen["$package_name"]=1
      printf '%s|\n' "$package_name"
    done <<< "$packages"
  fi
  (( ${#seen[@]} > 0 )) || return 1
}

run_android_start() {
  local start_kind="$1"
  local value="$2"
  local am_bin=""
  local output=""
  local rc=0
  local controller_fallback_allowed=0

  am_bin="$(android_bin am 2>/dev/null || true)"
  if [[ -z "$am_bin" ]]; then
    controller_fallback_allowed=1
    rc=127
  fi

  if [[ "$start_kind" == package ]]; then
    valid_package_name "$value" || {
      printf '%s\n' 'Invalid Android package name.'
      return 64
    }
    # Do not gate the launch on `pm path`: vendor Android builds can expose
    # `am` while restricting package-manager reads to the shell UID. The exact
    # package-scoped MAIN/LAUNCHER resolver below remains the authority and
    # reports a missing package without changing package state.
    if [[ -n "$am_bin" ]]; then
      output="$("$am_bin" start --user 0 -a android.intent.action.MAIN \
        -c android.intent.category.LAUNCHER -p "$value" 2>&1)" || rc=$?
    fi
  else
    valid_intent_action "$value" || {
      printf '%s\n' 'Invalid Android intent action.'
      return 64
    }
    if [[ -n "$am_bin" ]]; then
      output="$("$am_bin" start --user 0 -a "$value" 2>&1)" || rc=$?
    fi
  fi

  # `am` normally returns non-zero for resolver failures. Also catch the
  # common textual error form so a vendor shell wrapper cannot report a false
  # success with an empty/failed activity launch.
  if (( rc == 0 )) && grep -Eiq '(^|[[:space:]])(Error|Exception):|Background activity start denied' <<< "$output"; then
    rc=1
  fi
  if (( rc == 0 )); then
    if [[ -n "$output" ]]; then
      printf '%s' "$output" | head -c "$MAX_PAYLOAD_BYTES"
      printf '\n'
    fi
    return 0
  fi
  if [[ -n "$output" ]]; then
    # Keep the broker response bounded; Android's actual error remains visible
    # while a runaway vendor diagnostic cannot fill the shared runtime.
    printf '%s' "$output" | head -c "$MAX_PAYLOAD_BYTES" >&2
    printf '\n' >&2
  fi

  if grep -Eiq 'Background activity start denied|SecurityException|Permission Denial|not allowed to start activity|background.*start.*not allowed' <<< "$output"; then
    controller_fallback_allowed=1
  fi

  if [[ "$start_kind" == package ]] && (( controller_fallback_allowed )) \
    && command -v termux-open-url >/dev/null 2>&1; then
    # On Android 16 a Termux shell command may be denied while a visible
    # companion Activity may still launch the exact package. This fallback is
    # deliberately a fixed custom URI, not an arbitrary Android intent bridge.
    if termux-open-url "fedora-shell://android/launch?package=$value" \
      >/dev/null 2>&1; then
      printf '%s\n' "Android controller launch requested for $value"
      return 0
    fi
  fi
  return "$rc"
}

write_response() {
  local request_id="$1"
  local rc="$2"
  local status="$3"
  local payload_file="$4"
  broker_paths_safe || {
    log "broker queue path became unavailable or symlinked"
    return 126
  }
  local temporary=""
  temporary="$(mktemp "$RESPONSE_DIR/.${request_id}.response.XXXXXX")" || {
    log "could not create an atomic response temporary file for $request_id"
    return 1
  }
  {
    printf 'status=%s\n' "$status"
    printf 'exit_code=%s\n' "$rc"
    printf '\n'
    if [[ -r "$payload_file" ]]; then
      head -c "$MAX_PAYLOAD_BYTES" "$payload_file"
    fi
  } > "$temporary"
  chmod 600 "$temporary" 2>/dev/null || true
  mv -f -- "$temporary" "$RESPONSE_DIR/$request_id.response"
}

process_request() {
  local request_file="$1"
  local request_id="${request_file##*/}"
  request_id="${request_id%.request}"
  broker_paths_safe || return 126
  [[ "$request_id" =~ ^[a-zA-Z0-9._-]+$ ]] || return 0
  [[ -f "$request_file" && ! -L "$request_file" ]] || return 0

  local version="" operation="" scope="user" package_name="" action=""
  local key value extra=0 version_seen=0 operation_seen=0 scope_seen=0
  local package_seen=0 action_seen=0
  while IFS='=' read -r key value; do
    case "$key" in
      version)
        if (( ! version_seen )); then version="$value"; version_seen=1; else extra=1; fi
        ;;
      operation)
        if (( ! operation_seen )); then operation="$value"; operation_seen=1; else extra=1; fi
        ;;
      scope)
        if (( ! scope_seen )); then scope="$value"; scope_seen=1; else extra=1; fi
        ;;
      package)
        if (( ! package_seen )); then package_name="$value"; package_seen=1; else extra=1; fi
        ;;
      action)
        if (( ! action_seen )); then action="$value"; action_seen=1; else extra=1; fi
        ;;
      '') ;;
      *) extra=1 ;;
    esac
  done < "$request_file"

  local payload_file=""
  payload_file="$(mktemp "$BROKER_DIR/.payload.XXXXXX")" || {
    log "could not create a request payload temporary file for $request_id"
    rm -f -- "$request_file"
    return 1
  }
  local rc=0 status=ok
  if [[ "$version" != 1 || "$operation" == "" || "$extra" == 1 ]]; then
    printf '%s\n' 'Malformed Android bridge request.' > "$payload_file"
    rc=64
    status=error
  else
    case "$operation" in
      list-apps)
        if (( package_seen || action_seen )); then
          printf '%s\n' 'Malformed Android app-list request.' > "$payload_file"
          rc=64
          status=error
        elif list_apps "$scope" > "$payload_file"; then
          :
        else
          rc=$?
          status=error
          printf '%s\n' 'Android package query is unavailable.' > "$payload_file"
        fi
        ;;
      launch-package)
        if (( ! package_seen || action_seen || scope_seen )); then
          printf '%s\n' 'Malformed Android package-launch request.' > "$payload_file"
          rc=64
          status=error
        elif run_android_start package "$package_name" > "$payload_file"; then
          :
        else
          rc=$?
          status=error
        fi
        ;;
      launch-intent)
        if (( ! action_seen || package_seen || scope_seen )); then
          printf '%s\n' 'Malformed Android intent-launch request.' > "$payload_file"
          rc=64
          status=error
        elif run_android_start intent "$action" > "$payload_file"; then
          :
        else
          rc=$?
          status=error
        fi
        ;;
      *)
        printf '%s\n' 'Unsupported Android bridge operation.' > "$payload_file"
        rc=64
        status=error
        ;;
    esac
  fi

  write_response "$request_id" "$rc" "$status" "$payload_file"
  rm -f -- "$payload_file" "$request_file"
}

cleanup() {
  # Remove only broker-owned runtime files. In particular, never leave a
  # queued launch request to be replayed by a later Linux session after an
  # interrupted stop.
  broker_paths_safe || return 0
  find "$BROKER_DIR" -maxdepth 1 -type f -name '.payload.*' -delete 2>/dev/null || true
  find "$REQUEST_DIR" "$RESPONSE_DIR" -maxdepth 1 \
    \( -type f -o -type l \) -name '*.*' -delete 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if (( $# != 2 )) || [[ "$1" != --serve ]] || [[ ! "$2" =~ ^[0-9]+$ ]]; then
  usage
  exit 64
fi
PARENT_PID="$2"

for broker_path in "$BROKER_DIR" "$REQUEST_DIR" "$RESPONSE_DIR"; do
  if [[ -L "$broker_path" ]]; then
    log "refusing symlinked broker path: $broker_path"
    exit 126
  fi
done
if ! mkdir -p "$REQUEST_DIR" "$RESPONSE_DIR"; then
  log "could not create broker queue directories"
  exit 1
fi
for broker_path in "$BROKER_DIR" "$REQUEST_DIR" "$RESPONSE_DIR"; do
  if [[ -L "$broker_path" ]]; then
    log "refusing broker path changed to symlink: $broker_path"
    exit 126
  fi
done
chmod 700 "$BROKER_DIR" "$REQUEST_DIR" "$RESPONSE_DIR" 2>/dev/null || true
broker_paths_safe || {
  log "broker queue path failed its final safety check"
  exit 126
}
log "started for parent PID $PARENT_PID"

while :; do
  broker_paths_safe || {
    log "broker queue path became unavailable or symlinked"
    exit 126
  }
  # When start.sh is gone, stop serving requests. This also handles an
  # interrupted Termux session without relying on a second supervisor.
  kill -0 "$PARENT_PID" 2>/dev/null || exit 0

  request_file=""
  while IFS= read -r -d '' candidate; do
    request_file="$candidate"
    break
  done < <(find "$REQUEST_DIR" -maxdepth 1 -type f -name '*.request' -print0 2>/dev/null | sort -z || true)
  if [[ -n "$request_file" ]]; then
    process_request "$request_file" || log "request processing failed: $request_file"
  else
    # Keep abandoned replies bounded without touching anything outside the
    # project-owned response directory.
    find "$RESPONSE_DIR" -maxdepth 1 -type f -name '*.response' -mmin +10 -delete 2>/dev/null || true
    sleep "$BROKER_POLL_INTERVAL"
  fi
done
