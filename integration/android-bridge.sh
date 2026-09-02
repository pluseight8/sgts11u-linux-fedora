#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-android-bridge-v2
#
# This is a small, non-networked Android client. It can be called from Termux
# or from a Fedora desktop entry through the bind-mounted project tree. When a
# PRoot guest cannot see Android /system/bin, start.sh provides the matching
# local file broker in shared-tmp.

FEDORA_HOME="${HOME:-/data/data/com.termux/files/home}"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG="$SCRIPT_DIR/android-apps.conf"
if [[ ! -r "$APP_CONFIG" && -r /usr/local/share/fedora-shell/android-apps.conf ]]; then
  APP_CONFIG=/usr/local/share/fedora-shell/android-apps.conf
fi
[[ -f "$APP_CONFIG" && ! -L "$APP_CONFIG" ]] || APP_CONFIG=""
FEDORA_ANDROID_BRIDGE_DIR="${FEDORA_ANDROID_BRIDGE_DIR:-/tmp/fedora-runtime/android-bridge}"
FEDORA_ANDROID_BRIDGE_TIMEOUT="${FEDORA_ANDROID_BRIDGE_TIMEOUT:-12}"
if [[ ! "$FEDORA_ANDROID_BRIDGE_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  FEDORA_ANDROID_BRIDGE_TIMEOUT=12
fi
FEDORA_ANDROID_APPS_SCOPE="${FEDORA_ANDROID_APPS_SCOPE:-all}"
case "$FEDORA_ANDROID_APPS_SCOPE" in
  user|all) ;;
  *)
    printf 'Unknown FEDORA_ANDROID_APPS_SCOPE=%s; using user scope.\n' \
      "$FEDORA_ANDROID_APPS_SCOPE" >&2
    FEDORA_ANDROID_APPS_SCOPE=user
    ;;
esac

usage() {
  cat >&2 <<'EOF'
Usage: fedora-android-bridge COMMAND [ARGUMENT]

Read-only/status:
  battery | charging-state | battery-temperature | brightness | volume
  orientation | refresh-rate | network-state | audio-devices
  list-apps [--all]       list launchable/user Android packages (read-only)

User-triggered navigation:
  open-settings | open-wifi-settings | open-bluetooth-settings
  launch-app ID           only IDs in integration/android-apps.conf
  launch-package PACKAGE  start one exact installed Android package
  sync-apps               refresh Fedora user desktop entries for Android apps
  clipboard-read
  share-file PATH         shared storage or Fedora bridge share directory only
  launch-camera

This bridge is read-only with respect to Android settings and device policy.
It does not provide setters for brightness, volume, clipboard, vibration or
package state. User-triggered app/settings navigation is not a policy change.
Android applications are displayed by Android's own SurfaceFlinger above the
Fedora/Termux:X11 surface; this is a foreground hand-off, not native Linux
window embedding.
EOF
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

require_api() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Termux:API command is unavailable: %s\nInstall the matching Termux:API add-on and grant its permissions.\n' "$1" >&2
    exit 1
  }
}

valid_intent_action() {
  [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$ ]]
}

valid_package_name() {
  [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]]
}

path_parents_safe() {
  local path="$1"
  local current="${path%/*}"
  case "$path" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$path" in
    */../*|*/..|*/./*|*/.) return 1 ;;
  esac
  [[ -n "$current" ]] || current=/
  while [[ "$current" != / ]]; do
    [[ ! -L "$current" && ( ! -e "$current" || -d "$current" ) ]] || return 1
    current="${current%/*}"
    [[ -n "$current" ]] || current=/
  done
}

broker_request() {
  local operation="$1"
  local value="${2:-}"
  local request_dir="$FEDORA_ANDROID_BRIDGE_DIR/requests"
  local response_dir="$FEDORA_ANDROID_BRIDGE_DIR/responses"
  local request_id temporary request_file response_file
  local status exit_code payload tries=0

  path_parents_safe "$FEDORA_ANDROID_BRIDGE_DIR" \
    && path_parents_safe "$request_dir" \
    && path_parents_safe "$response_dir" \
    && [[ ! -L "$FEDORA_ANDROID_BRIDGE_DIR" && ! -L "$request_dir" && ! -L "$response_dir" ]] || {
    printf '%s\n' 'Android bridge broker path is a symlink; refusing the request.' >&2
    return 126
  }
  [[ -d "$request_dir" && -d "$response_dir" ]] || {
    printf '%s\n' 'Android bridge broker is not running; keep the Termux:X11 Activity visible and retry.' >&2
    return 127
  }
  request_id="$$.${RANDOM:-0}.$(date +%s 2>/dev/null || printf 0)"
  [[ "$request_id" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 64
  temporary="$(mktemp "$request_dir/.fedora-request.XXXXXX")" || {
    printf '%s\n' 'Could not create a temporary Android bridge request.' >&2
    return 1
  }
  request_file="$request_dir/$request_id.request"
  response_file="$response_dir/$request_id.response"

  case "$operation" in
    list-apps)
      [[ "$value" == user || "$value" == all ]] || {
        rm -f -- "$temporary"
        return 64
      }
      if ! printf 'version=1\noperation=list-apps\nscope=%s\n\n' "$value" > "$temporary"; then
        rm -f -- "$temporary"
        return 1
      fi
      ;;
    launch-package)
      valid_package_name "$value" || {
        rm -f -- "$temporary"
        return 64
      }
      if ! printf 'version=1\noperation=launch-package\npackage=%s\n\n' "$value" > "$temporary"; then
        rm -f -- "$temporary"
        return 1
      fi
      ;;
    launch-intent)
      valid_intent_action "$value" || {
        rm -f -- "$temporary"
        return 64
      }
      if ! printf 'version=1\noperation=launch-intent\naction=%s\n\n' "$value" > "$temporary"; then
        rm -f -- "$temporary"
        return 1
      fi
      ;;
    *)
      rm -f -- "$temporary"
      return 64
      ;;
  esac
  chmod 600 "$temporary" 2>/dev/null || true
  if ! mv -f -- "$temporary" "$request_file"; then
    rm -f -- "$temporary"
    printf '%s\n' 'Could not queue the Android bridge request.' >&2
    return 1
  fi

  while (( tries < FEDORA_ANDROID_BRIDGE_TIMEOUT * 10 )); do
    if [[ -f "$response_file" && ! -L "$response_file" ]]; then
      status="$(sed -n 's/^status=//p' "$response_file" | sed -n '1p' || true)"
      exit_code="$(sed -n 's/^exit_code=//p' "$response_file" | sed -n '1p' || true)"
      payload="$(awk 'BEGIN { body = 0 } /^$/ { body = 1; next } body { print }' "$response_file" || true)"
      rm -f -- "$response_file"
      # A response is data from the project-owned broker, not a shell script.
      # Validate every control field and fail closed on a malformed or
      # tampered response; in particular, an error with exit_code=0 must not
      # be reported as a successful Android launch.
      [[ "$status" == ok || "$status" == error ]] || return 1
      [[ "$exit_code" =~ ^(0|[1-9][0-9]?|[12][0-9][0-9]|25[0-5])$ ]] || return 1
      [[ -z "$payload" ]] || printf '%s\n' "$payload"
      if [[ "$status" == ok ]]; then
        [[ "$exit_code" == 0 ]] || return "$exit_code"
        return 0
      fi
      [[ "$exit_code" == 0 ]] && exit_code=1
      return "$exit_code"
    fi
    sleep 0.1
    ((tries += 1))
  done
  rm -f -- "$request_file" "$response_file"
  printf '%s\n' 'Timed out waiting for the Android bridge broker; no Android policy was changed.' >&2
  return 124
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

local_package_list() {
  local scope="${1:-user}"
  local pm_bin="" cmd_bin=""
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

list_apps_local() {
  local scope="${1:-user}"
  local packages="" query="" cmd_bin="" line candidate package_name activity
  local package_list_available=0
  local -A allowed=() seen=()
  if packages="$(local_package_list "$scope" 2>/dev/null)"; then
    package_list_available=1
  else
    # Android may expose the read-only activity resolver while denying the
    # package inventory to an ordinary Termux UID. `all` can still be safely
    # enumerated from resolver output; `user` requires the package inventory
    # to avoid accidentally widening the historical third-party scope.
    [[ "$scope" == all ]] || return $?
  fi
  while IFS= read -r line; do
    package_name="${line#package:}"
    valid_package_name "$package_name" || continue
    allowed["$package_name"]=1
  done <<< "$packages"

  if cmd_bin="$(android_bin cmd 2>/dev/null)"; then
    query="$("$cmd_bin" package query-activities --brief --components --user 0 \
      -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>/dev/null || true)"
    while IFS= read -r line; do
      candidate="${line##* }"
      [[ "$candidate" == */* ]] || continue
      package_name="${candidate%%/*}"
      activity="${candidate#*/}"
      valid_package_name "$package_name" || continue
      [[ "$activity" =~ ^[a-zA-Z0-9_.$]+$ ]] || continue
      if [[ "$scope" == all || -n "${allowed[$package_name]:-}" ]]; then
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

list_apps() {
  local scope="${1:-user}"
  [[ "$scope" == user || "$scope" == all ]] || return 64
  # Finding /system/bin/pm is not proof that the unprivileged Termux UID can
  # use it. Android 16/vendor builds sometimes expose the executable but
  # reject the query; in that case fall through to the same-UID broker instead
  # of failing before the broker gets a chance to answer.
  if android_bin pm >/dev/null 2>&1 || android_bin cmd >/dev/null 2>&1; then
    if list_apps_local "$scope"; then
      return 0
    fi
  fi
  broker_request list-apps "$scope"
}

launch_android_start() {
  local start_kind="$1"
  local value="$2"
  local am_bin="" output="" rc=0
  local controller_fallback_allowed=0

  if [[ "$start_kind" == package ]]; then
    valid_package_name "$value" || {
      printf '%s\n' 'Invalid Android package name.' >&2
      return 64
    }
  else
    valid_intent_action "$value" || {
      printf '%s\n' 'Invalid Android intent action.' >&2
      return 64
    }
  fi

  if am_bin="$(android_bin am 2>/dev/null)"; then
    if [[ "$start_kind" == package ]]; then
      # Some vendor builds allow `am start` while restricting `pm path` for
      # the Termux UID. Let Android's exact package resolver be authoritative.
      output="$("$am_bin" start --user 0 -a android.intent.action.MAIN \
        -c android.intent.category.LAUNCHER -p "$value" 2>&1)" || rc=$?
    else
      output="$("$am_bin" start --user 0 -a "$value" 2>&1)" || rc=$?
    fi
    if (( rc == 0 )) && grep -Eiq '(^|[[:space:]])(Error|Exception):|Background activity start denied' <<< "$output"; then
      rc=1
    fi
    if (( rc == 0 )); then
      [[ -z "$output" ]] || printf '%s\n' "$output"
      return 0
    fi
    [[ -z "$output" ]] || printf '%s\n' "$output" >&2
    # Only hand a package launch to the foreground Android Activity when the
    # shell UID was rejected by Android's background-start security policy.
    # Resolver errors (unknown package, missing launcher, malformed intent)
    # must remain errors instead of being reported as a false success.
    if grep -Eiq 'Background activity start denied|SecurityException|Permission Denial|not allowed to start activity|background.*start.*not allowed' <<< "$output"; then
      controller_fallback_allowed=1
    fi
  else
    # A PRoot guest often cannot see Android's /system/bin/am at all. The
    # broker is the normal host-UID path; the controller URI is an additional
    # foreground fallback when the client itself runs in Termux.
    controller_fallback_allowed=1
  fi
  if [[ "$start_kind" == package ]]; then
    # Android 16/vendor builds may reject a shell-UID `am start` even though
    # the same package can be launched from a visible Android Activity. Ask
    # the companion Fedora Shell APK to perform that foreground PackageManager
    # launch through its narrow custom URI. The URI contains only the already
    # validated package ID; it is not a general intent or shell channel.
    if (( controller_fallback_allowed )) && command -v termux-open-url >/dev/null 2>&1; then
      if termux-open-url "fedora-shell://android/launch?package=$value" \
        >/dev/null 2>&1; then
        printf 'Android controller launch requested for %s\n' "$value"
        return 0
      fi
    fi
    broker_request launch-package "$value"
  else
    broker_request launch-intent "$value"
  fi
}

read_app_target() {
  local app_id="$1"
  [[ "$app_id" =~ ^[a-z0-9-]+$ ]] || return 1
  [[ -r "$APP_CONFIG" ]] || return 1
  awk -F'|' -v wanted="$app_id" '$1 == wanted { print $3; exit }' "$APP_CONFIG"
}

under_allowed_file_root() {
  local candidate="$1"
  local shared_root
  local bridge_root="$FEDORA_HOME/.fedora-shell/share"
  # A lexical prefix check is bypassable with symlinks and `..`. Fail closed
  # when canonicalization is unavailable instead of silently weakening the
  # allowlist. The guest bind uses /home/<user>/Android; the host uses
  # $HOME/storage/shared, so support both spellings without broadening access.
  command -v realpath >/dev/null 2>&1 || return 1
  candidate="$(realpath -- "$candidate" 2>/dev/null)" || return 1
  if [[ -d "$bridge_root" ]]; then
    bridge_root="$(realpath -- "$bridge_root" 2>/dev/null || true)"
  else
    bridge_root=""
  fi
  for shared_root in \
    "$FEDORA_HOME/storage/shared" \
    "$FEDORA_HOME/Android" \
    /home/*/Android; do
    [[ -d "$shared_root" ]] || continue
    shared_root="$(realpath -- "$shared_root" 2>/dev/null)" || continue
    [[ "$candidate" == "$shared_root"/* ]] && return 0
  done
  [[ -n "$bridge_root" && "$candidate" == "$bridge_root"/* ]]
}

sync_app_desktops() {
  local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  local catalog="" package_name component desktop_name desktop temp label
  local scope="${FEDORA_ANDROID_APPS_SCOPE:-all}"
  local count=0
  local -A current=()
  case "$scope" in
    user|all) ;;
    *)
      printf 'Unknown Android application scope: %s\n' "$scope" >&2
      return 64
      ;;
  esac
  path_parents_safe "$desktop_dir" || {
    printf 'Refusing an unsafe desktop directory path: %s\n' "$desktop_dir" >&2
    return 126
  }
  [[ ! -L "$desktop_dir" ]] || {
    printf 'Refusing to use symlinked desktop directory: %s\n' "$desktop_dir" >&2
    return 126
  }
  mkdir -p "$desktop_dir"
  [[ -d "$desktop_dir" && ! -L "$desktop_dir" ]] || {
    printf 'Desktop directory became unsafe during setup: %s\n' "$desktop_dir" >&2
    return 126
  }
  catalog="$(list_apps "$scope")" || return $?

  while IFS='|' read -r package_name component; do
    valid_package_name "$package_name" || continue
    # Dots are legal in a desktop filename, so keep the exact package ID and
    # avoid the collisions caused by replacing dots with underscores.
    # Keep the historical filename prefix for compatibility with entries
    # already generated by older versions. The scope is recorded in metadata,
    # so the filename is not used as a security or policy decision.
    desktop_name="fedora-android-user-${package_name}.desktop"
    desktop="$desktop_dir/$desktop_name"
    temp="$(mktemp "$desktop_dir/.fedora-android.XXXXXX")"
    if [[ -L "$desktop" ]]; then
      printf 'Skipping symlinked Android desktop entry: %s\n' "$desktop" >&2
      rm -f -- "$temp"
      continue
    fi
    if [[ -e "$desktop" ]] && {
      [[ ! -f "$desktop" ]] || ! grep -Fq 'X-Fedora-Shell-Android-Dynamic=true' "$desktop";
    }; then
      printf 'Preserving non-project Android desktop entry: %s\n' "$desktop" >&2
      rm -f -- "$temp"
      continue
    fi
    current["$package_name"]=1
    label="Android: $package_name"
    {
      printf '%s\n' '[Desktop Entry]'
      printf '%s\n' 'Type=Application'
      printf 'Name=%s\n' "$label"
      printf '%s\n' 'Comment=Open this Android application above Fedora'
      printf 'Exec=/usr/local/bin/fedora-android-bridge launch-package %s\n' "$package_name"
      printf '%s\n' 'Icon=application-x-executable'
      printf '%s\n' 'Terminal=false'
      printf '%s\n' 'Categories=Utility;'
      printf '%s\n' 'X-Fedora-Shell-Android=true'
      printf '%s\n' 'X-Fedora-Shell-Android-Dynamic=true'
      printf 'X-Fedora-Shell-Android-Scope=%s\n' "$scope"
      printf 'X-Fedora-Shell-Android-Package=%s\n' "$package_name"
      [[ -z "$component" ]] || printf 'X-Fedora-Shell-Launcher=%s\n' "$component"
    } > "$temp"
    chmod 0644 "$temp"
    [[ ! -L "$desktop" ]] || {
      printf 'Android desktop entry became a symlink during setup: %s\n' "$desktop" >&2
      rm -f -- "$temp"
      continue
    }
    mv -f -- "$temp" "$desktop"
    count=$((count + 1))
  done <<< "$catalog"

  # Reconcile only files created by this component. Never remove a user's
  # ordinary desktop file, symlink, or hand-written Android entry.
  while IFS= read -r -d '' desktop; do
    [[ -L "$desktop" ]] && continue
    grep -Fq 'X-Fedora-Shell-Android-Dynamic=true' "$desktop" 2>/dev/null || continue
    package_name="$(sed -n 's/^X-Fedora-Shell-Android-Package=//p' "$desktop" | sed -n '1p' || true)"
    [[ -n "${current[$package_name]:-}" ]] && continue
    rm -f -- "$desktop"
  done < <(find "$desktop_dir" -maxdepth 1 -type f \
    -name 'fedora-android-user-*.desktop' -print0 2>/dev/null || true)
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
  fi
  printf 'Android desktop entries refreshed: %d launchable package(s), scope=%s\n' \
    "$count" "$scope"
}

if (( $# == 0 )); then
  usage
  exit 64
fi

command_name="$1"
shift
case "$command_name" in
  battery)
    require_api termux-battery-status
    exec termux-battery-status
    ;;
  charging-state|battery-temperature)
    require_api termux-battery-status
    field=status
    [[ "$command_name" == battery-temperature ]] && field=temperature
    termux-battery-status | awk -v field="$field" 'BEGIN { FS = "[ :{},\"]+" } $0 ~ field { print; found=1 } END { if (!found) exit 1 }'
    ;;
  brightness)
    settings_bin="$(android_bin settings)"
    printf 'mode='; "$settings_bin" get system screen_brightness_mode || true
    printf 'value='; "$settings_bin" get system screen_brightness || true
    ;;
  volume)
    require_api termux-volume
    exec termux-volume
    ;;
  orientation)
    settings_bin="$(android_bin settings)"
    printf 'accelerometer_rotation='; "$settings_bin" get system accelerometer_rotation || true
    printf 'user_rotation='; "$settings_bin" get system user_rotation || true
    ;;
  refresh-rate)
    settings_bin="$(android_bin settings)"
    printf 'peak_refresh_rate='; "$settings_bin" get system peak_refresh_rate || true
    printf 'min_refresh_rate='; "$settings_bin" get system min_refresh_rate || true
    if [[ -x /system/bin/dumpsys ]]; then
      /system/bin/dumpsys display 2>/dev/null \
        | grep -E 'DisplayDeviceInfo|modeId|refreshRate|mSupportedModes' \
        | sed -n '1,120p' || true
    fi
    ;;
  network-state)
    if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
      exec termux-wifi-connectioninfo
    fi
    settings_bin="$(android_bin settings)"
    "$settings_bin" get global airplane_mode_on || true
    ;;
  audio-devices)
    require_api termux-volume
    exec termux-volume
    ;;
  open-settings|open-wifi-settings|open-bluetooth-settings)
    case "$command_name" in
      open-settings) action=android.settings.SETTINGS ;;
      open-wifi-settings) action=android.settings.WIFI_SETTINGS ;;
      open-bluetooth-settings) action=android.settings.BLUETOOTH_SETTINGS ;;
    esac
    launch_android_start intent "$action"
    ;;
  list-apps)
    scope=user
    if (( $# > 1 )); then usage; exit 64; fi
    if (( $# == 1 )); then
      [[ "$1" == --all ]] || { usage; exit 64; }
      scope=all
    fi
    list_apps "$scope"
    ;;
  launch-app)
    (( $# == 1 )) || { usage; exit 64; }
    target="$(read_app_target "$1")"
    [[ -n "$target" ]] || {
      printf 'Unknown Android app id: %s\n' "$1" >&2
      exit 64
    }
    launch_target_kind=""
    case "$target" in
      intent:*) launch_target_kind=intent; target="${target#intent:}" ;;
      package:*) launch_target_kind=package; target="${target#package:}" ;;
      *) printf '%s\n' 'Unsupported target in allowlist' >&2; exit 64 ;;
    esac
    launch_android_start "$launch_target_kind" "$target"
    ;;
  launch-package)
    (( $# == 1 )) || { usage; exit 64; }
    valid_package_name "$1" || {
      printf '%s\n' 'Invalid Android package name.' >&2
      exit 64
    }
    launch_android_start package "$1"
    ;;
  sync-apps)
    (( $# == 0 )) || { usage; exit 64; }
    sync_app_desktops
    ;;
  clipboard-read)
    require_api termux-clipboard-get
    exec termux-clipboard-get
    ;;
  share-file)
    (( $# == 1 )) || { usage; exit 64; }
    [[ -f "$1" ]] || { printf 'Not a regular file: %s\n' "$1" >&2; exit 1; }
    under_allowed_file_root "$1" || {
      printf '%s\n' 'Only shared storage or the bridge share directory may be shared.' >&2
      exit 1
    }
    require_api termux-share
    exec termux-share --send "$1"
    ;;
  launch-camera)
    target="$(read_app_target camera || true)"
    [[ -n "$target" ]] || {
      printf '%s\n' 'Camera intent is missing or invalid in the allowlist' >&2
      exit 64
    }
    case "$target" in
      intent:*) launch_android_start intent "${target#intent:}" ;;
      package:*) launch_android_start package "${target#package:}" ;;
      *) printf '%s\n' 'Unsupported camera target in allowlist' >&2; exit 64 ;;
    esac
    ;;
  *)
    usage
    exit 64
    ;;
esac
