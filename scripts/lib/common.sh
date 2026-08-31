#!/data/data/com.termux/files/usr/bin/bash

# Shared, deliberately boring helpers for the Termux-side scripts.
# This file must remain POSIX-ish bash: it is also used by Termux:Widget.

FEDORA_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_PROJECT_ROOT="$(CDPATH='' cd -- "$FEDORA_SCRIPT_DIR/../.." && pwd)"
FEDORA_USER_HOME="${HOME:-}"

if [[ -z "$FEDORA_USER_HOME" ]]; then
  printf '%s\n' "HOME is not set; run this from Termux or set HOME explicitly." >&2
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 1
fi

FEDORA_STATE_DIR="${FEDORA_STATE_DIR:-$FEDORA_USER_HOME/.fedora-shell}"
FEDORA_CONFIG_FILE="${FEDORA_CONFIG_FILE:-$FEDORA_STATE_DIR/config.env}"

# Preserve explicit environment overrides while loading the persistent config.
# The config supplies defaults, but a command such as
# `FEDORA_GPU_MODE=software ./scripts/start.sh` must be able to override it.
fedora_config_override_names=()
fedora_config_override_values=()
for fedora_config_variable in \
  FEDORA_CONTAINER \
  FEDORA_RELEASE \
  FEDORA_IMAGE \
  FEDORA_ARCH \
  FEDORA_DISPLAY \
  FEDORA_GPU_MODE \
  FEDORA_AUDIO_MODE \
  FEDORA_MEMORY_PROFILE \
  FEDORA_SETTINGS_DAEMON \
  FEDORA_LAUNCH_TERMINAL \
  FEDORA_KEYRING_MODE \
  FEDORA_SEARCH_MODE \
  FEDORA_PORTAL_MODE \
  FEDORA_USER \
  FEDORA_TERMUX_X11_FULLSCREEN \
  FEDORA_NESTED_SCALE \
  FEDORA_NESTED_MODE \
  FEDORA_NESTED_MODE_SPECS \
  FEDORA_TERMUX_X11_LEGACY_DRAWING \
  FEDORA_TERMUX_X11_FORCE_BGRA \
  FEDORA_CHECKOUT_ROOT \
  FEDORA_INSTALL_ROOT \
  FEDORA_SHARED_STORAGE \
  FEDORA_GUEST_PROJECT_ROOT; do
  if [[ -v "$fedora_config_variable" ]]; then
    fedora_config_override_names+=("$fedora_config_variable")
    fedora_config_override_values+=("${!fedora_config_variable}")
  fi
done

# The config is created by install.sh with mode 0600. Do not source a config
# from the repository: the installed state directory is the trust boundary.
if [[ -r "$FEDORA_CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$FEDORA_CONFIG_FILE"
fi
for fedora_config_index in "${!fedora_config_override_names[@]}"; do
  printf -v "${fedora_config_override_names[$fedora_config_index]}" '%s' \
    "${fedora_config_override_values[$fedora_config_index]}"
done
unset fedora_config_override_names fedora_config_override_values \
  fedora_config_variable fedora_config_index

: "${FEDORA_CONTAINER:=fedora-s11u}"
: "${FEDORA_RELEASE:=44}"
: "${FEDORA_IMAGE:=fedora:44}"
: "${FEDORA_ARCH:=aarch64}"
: "${FEDORA_DISPLAY:=:0}"
: "${FEDORA_GPU_MODE:=auto}"
: "${FEDORA_AUDIO_MODE:=auto}"
: "${FEDORA_MEMORY_PROFILE:=auto}"
: "${FEDORA_SETTINGS_DAEMON:=auto}"
: "${FEDORA_LAUNCH_TERMINAL:=auto}"
: "${FEDORA_KEYRING_MODE:=auto}"
: "${FEDORA_SEARCH_MODE:=auto}"
: "${FEDORA_PORTAL_MODE:=auto}"
: "${FEDORA_USER:=fedora}"
: "${FEDORA_TERMUX_X11_FULLSCREEN:=1}"
: "${FEDORA_NESTED_SCALE:=1}"
: "${FEDORA_NESTED_MODE:=auto}"
: "${FEDORA_NESTED_MODE_SPECS:=}"
: "${FEDORA_TERMUX_X11_LEGACY_DRAWING:=1}"
: "${FEDORA_TERMUX_X11_FORCE_BGRA:=0}"
: "${FEDORA_INSTALL_ROOT:=$FEDORA_USER_HOME/.local/share/fedora-shell}"
: "${FEDORA_SHARED_STORAGE:=$FEDORA_USER_HOME/storage/shared}"
: "${FEDORA_GUEST_PROJECT_ROOT:=/opt/fedora-shell}"

fedora_resolve_memory_profile() {
  local requested="${1:-auto}"
  local total_kib=""
  case "$requested" in
    low|balanced|performance)
      printf '%s\n' "$requested"
      ;;
    auto)
      total_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)"
      # Android reports usable host RAM rather than a desktop's free RAM. A
      # 12 GiB tablet normally lands below this 13 GiB threshold, so the
      # conservative session profile is selected without disabling Fedora.
      if [[ "$total_kib" =~ ^[0-9]+$ ]] && (( total_kib <= 13 * 1024 * 1024 )); then
        printf '%s\n' low
      else
        printf '%s\n' balanced
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

fedora_requested_memory_profile="$FEDORA_MEMORY_PROFILE"
if ! FEDORA_MEMORY_PROFILE="$(fedora_resolve_memory_profile "$fedora_requested_memory_profile")"; then
  printf '[fedora-shell][error] Unknown FEDORA_MEMORY_PROFILE=%s (use auto, low, balanced or performance).\n' \
    "$fedora_requested_memory_profile" >&2
  # This file is both sourced by launchers and executable as a library probe;
  # keep the direct-execution exit path explicit for both call modes.
  # shellcheck disable=SC2317
  return 1 2>/dev/null || exit 64
fi
unset fedora_requested_memory_profile

# The installed copy can be used after the checkout has moved. Prefer the
# conventional bootstrap location when it is a real checkout, then fall back
# to the directory containing the running script (useful for local testing).
if [[ -z "${FEDORA_CHECKOUT_ROOT:-}" ]]; then
  if [[ -d "$FEDORA_USER_HOME/fedora-galaxy/.git" ]]; then
    FEDORA_CHECKOUT_ROOT="$FEDORA_USER_HOME/fedora-galaxy"
  else
    FEDORA_CHECKOUT_ROOT="$FEDORA_PROJECT_ROOT"
  fi
fi

FEDORA_PROJECT_ITEMS=(
  scripts
  fedora
  gpu
  audio
  input
  integration
  README.md
  ARCHITECTURE.md
  INSTALL.md
  SECURITY.md
  STATUS.md
  TROUBLESHOOTING.md
  VERSIONS.md
)

FEDORA_TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
FEDORA_TERMUX_HOME="${FEDORA_USER_HOME}"
FEDORA_LOG_DIR="${FEDORA_STATE_DIR}/logs"
FEDORA_PID_DIR="${FEDORA_STATE_DIR}/pids"
FEDORA_BOOT_DIR="${FEDORA_USER_HOME}/.termux/boot"
FEDORA_WIDGET_DIR="${FEDORA_USER_HOME}/.shortcuts"
export FEDORA_PROJECT_ROOT FEDORA_TERMUX_PREFIX FEDORA_TERMUX_HOME
export FEDORA_BOOT_DIR FEDORA_WIDGET_DIR

fedora_log() {
  local message="$*"
  printf '[fedora-shell] %s\n' "$message" >&2
  if [[ -n "${FEDORA_LOG_FILE:-}" ]]; then
    printf '%s\n' "$message" >> "$FEDORA_LOG_FILE"
  fi
}

fedora_warn() {
  local message="$*"
  printf '[fedora-shell][warning] %s\n' "$message" >&2
  if [[ -n "${FEDORA_LOG_FILE:-}" ]]; then
    printf '[warning] %s\n' "$message" >> "$FEDORA_LOG_FILE"
  fi
}

fedora_die() {
  local message="$*"
  printf '[fedora-shell][error] %s\n' "$message" >&2
  if [[ -n "${FEDORA_LOG_FILE:-}" ]]; then
    printf '[error] %s\n' "$message" >> "$FEDORA_LOG_FILE"
  fi
  return 1
}

fedora_have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

fedora_require_cmd() {
  fedora_have_cmd "$1" || fedora_die "Required command not found: $1"
}

fedora_is_termux() {
  # Do not infer Termux from the fallback path above: that path is also used
  # when a script is inspected on a normal Linux workstation.
  [[ -n "${TERMUX_VERSION:-}" ]] || [[ "${PREFIX:-}" == /data/data/*/files/usr ]]
}

fedora_require_termux() {
  fedora_is_termux || fedora_die "This command must run inside Termux on Android."
}

fedora_require_non_root() {
  local uid
  uid="$(id -u 2>/dev/null || printf 'unknown')"
  [[ "$uid" != 0 ]] || fedora_die "Root shell detected. This project intentionally requires ordinary Termux UID."
}

fedora_getprop() {
  local key="$1"
  if [[ -x /system/bin/getprop ]]; then
    /system/bin/getprop "$key" 2>/dev/null || true
  elif fedora_have_cmd getprop; then
    getprop "$key" 2>/dev/null || true
  fi
}

fedora_android_package_installed() {
  local package_name="$1"
  local pm_bin=/system/bin/pm
  if [[ ! -x "$pm_bin" ]]; then
    return 2
  fi
  "$pm_bin" path "$package_name" 2>/dev/null | grep -Fq 'package:'
}

fedora_init_state() {
  mkdir -p "$FEDORA_STATE_DIR" "$FEDORA_LOG_DIR" "$FEDORA_PID_DIR"
  chmod 700 "$FEDORA_STATE_DIR" "$FEDORA_LOG_DIR" "$FEDORA_PID_DIR" 2>/dev/null || true
}

fedora_init_log() {
  fedora_init_state
  FEDORA_LOG_FILE="${FEDORA_LOG_FILE:-$FEDORA_LOG_DIR/$(basename "$0").log}"
  export FEDORA_LOG_FILE
  : > "$FEDORA_LOG_FILE"
  chmod 600 "$FEDORA_LOG_FILE" 2>/dev/null || true
}

fedora_pd_bin() {
  if fedora_have_cmd proot-distro; then
    command -v proot-distro
  elif fedora_have_cmd pd; then
    command -v pd
  else
    return 1
  fi
}

fedora_require_pd() {
  FEDORA_PD_BIN="$(fedora_pd_bin)" || fedora_die "proot-distro is not installed. Run install.sh first."
  export FEDORA_PD_BIN
}

fedora_container_exists() {
  local pd_bin="${FEDORA_PD_BIN:-$(fedora_pd_bin 2>/dev/null || true)}"
  [[ -n "$pd_bin" ]] || return 1
  "$pd_bin" list --quiet 2>/dev/null | grep -Fxq "$FEDORA_CONTAINER"
}

fedora_require_container() {
  fedora_require_pd
  fedora_container_exists || fedora_die "Fedora container '$FEDORA_CONTAINER' is not installed. Run install.sh."
}

fedora_container_running() {
  local pd_bin="${FEDORA_PD_BIN:-$(fedora_pd_bin 2>/dev/null || true)}"
  [[ -n "$pd_bin" ]] || return 1
  "$pd_bin" ps 2>/dev/null | awk -v container="$FEDORA_CONTAINER" \
    'NR > 1 && $2 == container { found = 1 } END { exit(found ? 0 : 1) }'
}

fedora_pd_copy_to() {
  local source="$1"
  local destination="$2"
  [[ -f "$source" ]] || { fedora_die "Missing project file: $source"; return 1; }
  fedora_require_pd || return 1
  "$FEDORA_PD_BIN" copy "$source" "$FEDORA_CONTAINER:$destination"
}

# Run a command inside the guest with the host's shared tmp, the X11 socket
# when Termux:X11 has created it, and the installed project tree. The helper
# deliberately binds only the project tree and the user-granted shared
# storage; private Android app data is not exposed through this wrapper.
fedora_pd_login_as() {
  local login_user="$1"
  shift
  fedora_require_pd
  local -a args=(login --shared-tmp --user "$login_user" \
    --env "FEDORA_GUEST_PROJECT_ROOT=$FEDORA_GUEST_PROJECT_ROOT")
  if [[ -d "$FEDORA_TERMUX_PREFIX/tmp/.X11-unix" ]]; then
    args+=(--shared-x11)
  fi
  if [[ -d "$FEDORA_INSTALL_ROOT" ]]; then
    args+=(--bind "$FEDORA_INSTALL_ROOT:$FEDORA_GUEST_PROJECT_ROOT")
  fi
  if [[ -d "$FEDORA_SHARED_STORAGE" ]]; then
    args+=(--bind "$FEDORA_SHARED_STORAGE:/home/$FEDORA_USER/Android")
  fi
  args+=("$FEDORA_CONTAINER" --)
  "$FEDORA_PD_BIN" "${args[@]}" "$@"
}

fedora_pd_login() {
  fedora_pd_login_as "$FEDORA_USER" "$@"
}

fedora_pd_login_root() {
  fedora_pd_login_as root "$@"
}

fedora_sync_project_tree() {
  local source_root="$1"
  local target_root="$2"
  local item

  [[ -d "$source_root" ]] || {
    fedora_die "Project checkout does not exist: $source_root"
    return 1
  }
  [[ "$source_root" != "$target_root" ]] || return 0
  mkdir -p "$target_root"
  for item in "${FEDORA_PROJECT_ITEMS[@]}"; do
    [[ -e "$source_root/$item" ]] || {
      fedora_die "Project file is missing: $source_root/$item"
      return 1
    }
    # Preserve executable bits. cp -R alone can silently inherit the target
    # umask and was the reason a later git pull made launchers non-executable.
    cp -a -- "$source_root/$item" "$target_root/"
  done
}

fedora_free_kib() {
  df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4; exit }'
}

fedora_has_pid() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [[ -d "/proc/$pid" ]]
}

fedora_pid_matches() {
  local pid="$1"
  local needle="$2"
  fedora_has_pid "$pid" || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq -- "$needle"
}

fedora_kill_owned_pid() {
  local pid_file="$1"
  local marker="$2"
  [[ -f "$pid_file" ]] || return 0
  local pid
  pid="$(sed -n '1p' "$pid_file" 2>/dev/null || true)"
  if fedora_pid_matches "$pid" "$marker"; then
    kill "$pid" 2>/dev/null || true
    local tries=0
    while fedora_pid_matches "$pid" "$marker" && (( tries < 30 )); do
      sleep 0.1
      ((tries += 1))
    done
    if fedora_pid_matches "$pid" "$marker"; then
      fedora_warn "Process $pid did not stop after 3 seconds; sending SIGKILL."
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  rm -f -- "$pid_file"
}

fedora_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

fedora_confirm() {
  local prompt="$1"
  if fedora_is_true "${FEDORA_ASSUME_YES:-0}"; then
    return 0
  fi
  printf '%s [y/N] ' "$prompt" >&2
  local answer
  IFS= read -r answer || return 1
  [[ "$answer" == y || "$answer" == Y || "$answer" == yes || "$answer" == YES ]]
}

fedora_install_root() {
  printf '%s\n' "$FEDORA_INSTALL_ROOT"
}

fedora_install_owned_file() {
  local source="$1"
  local target="$2"
  local marker="$3"
  if [[ -L "$target" ]]; then
    fedora_die "Refusing to overwrite symlink: $target"
    return 1
  fi
  if [[ -e "$target" ]] && ! grep -Fq -- "$marker" "$target" 2>/dev/null; then
    fedora_die "Refusing to overwrite non-project file: $target"
    return 1
  fi
  mkdir -p "$(dirname -- "$target")"
  cp -- "$source" "$target"
  chmod 700 "$target"
}

fedora_remove_owned_file() {
  local target="$1"
  local marker="$2"
  [[ -e "$target" ]] || return 0
  if [[ -L "$target" ]]; then
    fedora_die "Refusing to remove symlink: $target"
    return 1
  fi
  if [[ ! -f "$target" ]]; then
    fedora_die "Refusing to remove non-file: $target"
    return 1
  fi
  if ! grep -Fq -- "$marker" "$target"; then
    fedora_die "Refusing to remove unowned file: $target"
    return 1
  fi
  rm -f -- "$target"
}
