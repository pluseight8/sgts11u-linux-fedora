#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-android-bridge-v1
# This is a small allowlisted client. It can be called from Termux or from a
# Fedora desktop entry through the bind-mounted project tree.

FEDORA_HOME="${HOME:-/data/data/com.termux/files/home}"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_CONFIG="$SCRIPT_DIR/android-apps.conf"
if [[ ! -r "$APP_CONFIG" && -r /usr/local/share/fedora-shell/android-apps.conf ]]; then
  APP_CONFIG=/usr/local/share/fedora-shell/android-apps.conf
fi

usage() {
  cat >&2 <<'EOF'
Usage: fedora-android-bridge COMMAND [ARGUMENT]

Read-only/status:
  battery | charging-state | battery-temperature | brightness | volume
  orientation | refresh-rate | network-state | audio-devices

Actions:
  brightness-set auto|0..255
  volume-set STREAM 0..N
  open-settings | open-wifi-settings | open-bluetooth-settings
  launch-app ID       (only IDs in integration/android-apps.conf)
  clipboard-read | clipboard-write TEXT
  share-file PATH      (shared storage or Fedora bridge share directory only)
  vibrate MILLISECONDS
  launch-camera
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

require_android_bin() {
  android_bin "$1" || { printf 'Android command is unavailable: %s\n' "$1" >&2; exit 1; }
}

require_api() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Termux:API command is unavailable: %s\nInstall the matching Termux:API add-on and grant its permissions.\n' "$1" >&2
    exit 1
  }
}

read_app_package() {
  local app_id="$1"
  [[ "$app_id" =~ ^[a-z0-9-]+$ ]] || return 1
  [[ -r "$APP_CONFIG" ]] || return 1
  awk -F'|' -v wanted="$app_id" '$1 == wanted { print $3; exit }' "$APP_CONFIG"
}

under_allowed_file_root() {
  local candidate="$1"
  local shared_root="$FEDORA_HOME/storage/shared"
  local bridge_root="$FEDORA_HOME/.fedora-shell/share"
  # A lexical prefix check is bypassable with symlinks and `..`. Fail closed
  # when canonicalization is unavailable instead of silently weakening the
  # allowlist.
  command -v realpath >/dev/null 2>&1 || return 1
  candidate="$(realpath -- "$candidate" 2>/dev/null)" || return 1
  shared_root="$(realpath -- "$shared_root" 2>/dev/null)" || return 1
  bridge_root="$(realpath -- "$bridge_root" 2>/dev/null)" || return 1
  [[ "$candidate" == "$shared_root"/* || "$candidate" == "$bridge_root"/* ]]
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
    if command -v termux-brightness >/dev/null 2>&1; then
      printf 'setter=termux-brightness\n'
    fi
    settings_bin="$(android_bin settings)"
    printf 'mode='; "$settings_bin" get system screen_brightness_mode || true
    printf 'value='; "$settings_bin" get system screen_brightness || true
    ;;
  brightness-set)
    (( $# == 1 )) || { usage; exit 64; }
    [[ "$1" == auto || "$1" =~ ^[0-9]{1,3}$ ]] || { printf '%s\n' 'brightness must be auto or 0..255' >&2; exit 64; }
    if command -v termux-brightness >/dev/null 2>&1; then
      exec termux-brightness "$1"
    fi
    printf '%s\n' 'termux-brightness is unavailable; no WRITE_SETTINGS fallback is attempted.' >&2
    exit 1
    ;;
  volume)
    require_api termux-volume
    exec termux-volume
    ;;
  volume-set)
    (( $# == 2 )) || { usage; exit 64; }
    case "$1" in music|ring|alarm|notification|system|call|accessibility|dtmf|voice_call) ;; *) printf '%s\n' 'unsupported audio stream' >&2; exit 64 ;; esac
    [[ "$2" =~ ^[0-9]+$ ]] || { printf '%s\n' 'volume must be a non-negative integer' >&2; exit 64; }
    require_api termux-volume
    exec termux-volume "$1" "$2"
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
    if [[ -x /system/bin/dumpsys ]]; then /system/bin/dumpsys display 2>/dev/null | grep -E 'DisplayDeviceInfo|modeId|refreshRate|mSupportedModes' | sed -n '1,120p' || true; fi
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
    am_bin="$(android_bin am)"
    case "$command_name" in
      open-settings) action=android.settings.SETTINGS ;;
      open-wifi-settings) action=android.settings.WIFI_SETTINGS ;;
      open-bluetooth-settings) action=android.settings.BLUETOOTH_SETTINGS ;;
    esac
    exec "$am_bin" start -a "$action"
    ;;
  launch-app)
    (( $# == 1 )) || { usage; exit 64; }
    package_name="$(read_app_package "$1")"
    [[ -n "$package_name" ]] || { printf 'Unknown Android app id: %s\n' "$1" >&2; exit 64; }
    [[ "$package_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]] || { printf '%s\n' 'Invalid package in allowlist' >&2; exit 64; }
    am_bin="$(android_bin am)"
    exec "$am_bin" start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$package_name"
    ;;
  clipboard-read)
    require_api termux-clipboard-get
    exec termux-clipboard-get
    ;;
  clipboard-write)
    (( $# == 1 )) || { usage; exit 64; }
    require_api termux-clipboard-set
    exec termux-clipboard-set "$1"
    ;;
  share-file)
    (( $# == 1 )) || { usage; exit 64; }
    [[ -f "$1" ]] || { printf 'Not a regular file: %s\n' "$1" >&2; exit 1; }
    under_allowed_file_root "$1" || { printf '%s\n' 'Only shared storage or the bridge share directory may be shared.' >&2; exit 1; }
    require_api termux-share
    exec termux-share --send "$1"
    ;;
  vibrate)
    (( $# == 1 )) || { usage; exit 64; }
    duration="$1"
    if [[ ! "$duration" =~ ^[0-9]+$ ]] || (( duration > 10000 )); then
      printf '%s\n' 'duration must be 0..10000 ms' >&2
      exit 64
    fi
    require_api termux-vibrate
    exec termux-vibrate -d "$duration"
    ;;
  launch-camera)
    package_name="$(read_app_package camera || true)"
    [[ "$package_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]] || {
      printf '%s\n' 'Camera package is missing or invalid in the allowlist' >&2
      exit 64
    }
    am_bin="$(android_bin am)"
    exec "$am_bin" start -a android.media.action.IMAGE_CAPTURE -p "$package_name"
    ;;
  *)
    usage
    exit 64
    ;;
esac
