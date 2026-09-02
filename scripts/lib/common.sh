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

# Validate the config path before reading it. This function is intentionally
# defined before the config source point and does not use the yet-untrusted
# FEDORA_LOG_FILE. Later state writes reuse the same parent-path check.
fedora_path_is_safe() {
  local path="$1"
  local current="${path%/*}"

  case "$path" in
    /*) ;;
    *)
      printf '[fedora-shell][error] Refusing a relative state path: %s\n' "$path" >&2
      return 1
      ;;
  esac

  if [[ "$path" == */../* || "$path" == */.. \
    || "$path" == */./* || "$path" == */. ]]; then
    printf '[fedora-shell][error] Refusing a path with dot components: %s\n' \
      "$path" >&2
    return 1
  fi

  [[ -n "$current" ]] || current="/"

  while [[ "$current" != "/" ]]; do
    if [[ -L "$current" || ( -e "$current" && ! -d "$current" ) ]]; then
      printf '[fedora-shell][error] Refusing an unsafe state path component: %s\n' "$current" >&2
      return 1
    fi
    current="${current%/*}"
    [[ -n "$current" ]] || current="/"
  done
}

# Destructive host-side operations are restricted to a child of the Termux
# home, and never to the checkout itself. This is intentionally narrower than
# fedora_path_is_safe: a custom path outside the user's home must be moved or
# explicitly handled by the user rather than silently removed by a script.
fedora_user_data_path_is_safe() {
  local path="$1"

  fedora_path_is_safe "$path" || return 1
  [[ "$path" == "$FEDORA_USER_HOME"/* ]] || return 1
  [[ "$path" != "$FEDORA_USER_HOME" ]] || return 1
  [[ ! -L "$path" && ( ! -e "$path" || -d "$path" ) ]] || return 1
  case "$path" in
    "$FEDORA_PROJECT_ROOT"|"$FEDORA_PROJECT_ROOT"/*)
      return 1
      ;;
  esac
}

# The installer may be invoked from the already-installed copy. That exact
# directory is a legitimate project target only when its ownership marker is
# present; a checkout or a similarly named unmarked directory is never
# accepted as an install root.
fedora_install_root_path_is_safe() {
  local path="$1"

  if fedora_user_data_path_is_safe "$path"; then
    return 0
  fi
  [[ "$path" == "$FEDORA_PROJECT_ROOT" ]] || return 1
  [[ ! -L "$path" && -d "$path" ]] || return 1
  # A real checkout must never become its own installation root.  The marker
  # is not sufficient proof of ownership: an interrupted or manually edited
  # checkout could contain one too.  The installed copy intentionally omits
  # .git, so this also distinguishes it from the source tree.
  [[ ! -e "$path/.git" ]] || return 1
  [[ -f "$path/.fedora-shell-install" && ! -L "$path/.fedora-shell-install" ]] || return 1
  grep -Fq '# fedora-shell-install-marker-v1' "$path/.fedora-shell-install" 2>/dev/null
}

if ! fedora_path_is_safe "$FEDORA_CONFIG_FILE" \
  || [[ -L "$FEDORA_CONFIG_FILE" \
    || ( -e "$FEDORA_CONFIG_FILE" && ! -f "$FEDORA_CONFIG_FILE" ) ]]; then
  printf '[fedora-shell][error] Refusing an unsafe Fedora config file: %s\n' \
    "$FEDORA_CONFIG_FILE" >&2
  return 1 2>/dev/null || exit 1
fi

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
  FEDORA_LINUX_MODE_PROFILE \
  FEDORA_LINUX_MODE_AUTO_RESUME \
  FEDORA_ANDROID_APPS_MODE \
  FEDORA_ANDROID_APPS_SCOPE \
  FEDORA_ANDROID_BRIDGE_POLL_INTERVAL \
  FEDORA_KEYBOARD_MODE \
  FEDORA_SETTINGS_DAEMON \
  FEDORA_LAUNCH_TERMINAL \
  FEDORA_KEYRING_MODE \
  FEDORA_SEARCH_MODE \
  FEDORA_PORTAL_MODE \
  FEDORA_CALENDAR_MODE \
  FEDORA_USER \
  FEDORA_TERMUX_X11_FULLSCREEN \
  FEDORA_NESTED_SCALE \
  FEDORA_NESTED_MODE \
  FEDORA_NESTED_XWAYLAND \
  FEDORA_NESTED_MODE_SPECS \
  FEDORA_DEVKIT_GDK_BACKEND \
  FEDORA_DEVKIT_PIPEWIRE \
  FEDORA_DEVKIT_PIPEWIRE_CONFIG \
  FEDORA_DEVKIT_DEBUG \
  FEDORA_TERMUX_X11_LEGACY_DRAWING \
  FEDORA_TERMUX_X11_FORCE_BGRA \
  FEDORA_TERMUX_X11_AUTO_OPEN \
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
: "${FEDORA_LINUX_MODE_PROFILE:=linux-focused}"
: "${FEDORA_LINUX_MODE_AUTO_RESUME:=0}"
: "${FEDORA_ANDROID_APPS_MODE:=auto}"
# `all` means all launchable packages visible to Android's read-only resolver,
# including preinstalled Samsung/Google/system apps. It is an enumeration
# scope, not a package-policy allowlist and never changes Android state.
: "${FEDORA_ANDROID_APPS_SCOPE:=all}"
: "${FEDORA_ANDROID_BRIDGE_POLL_INTERVAL:=0.25}"
# This is a Fedora/Termux focus profile, not an Android global-hook switch.
# When Linux Mode is active, ordinary hardware key events are delivered to the
# focused Termux:X11 Activity and then to the Wayland desktop. Android keeps
# ownership of protected global keys and SystemUI shortcuts.
: "${FEDORA_KEYBOARD_MODE:=linux}"
: "${FEDORA_SETTINGS_DAEMON:=auto}"
: "${FEDORA_LAUNCH_TERMINAL:=auto}"
: "${FEDORA_KEYRING_MODE:=auto}"
: "${FEDORA_SEARCH_MODE:=auto}"
: "${FEDORA_PORTAL_MODE:=auto}"
: "${FEDORA_CALENDAR_MODE:=auto}"
: "${FEDORA_USER:=fedora}"
# This is only a documented preference hint; the project never writes the
# Termux:X11 preference. Keep the safe default so Android bottom navigation is
# not accidentally hidden in a fresh configuration.
: "${FEDORA_TERMUX_X11_FULLSCREEN:=0}"
: "${FEDORA_NESTED_SCALE:=1}"
: "${FEDORA_NESTED_MODE:=auto}"
: "${FEDORA_NESTED_XWAYLAND:=auto}"
: "${FEDORA_NESTED_MODE_SPECS:=}"
: "${FEDORA_DEVKIT_GDK_BACKEND:=x11}"
: "${FEDORA_DEVKIT_PIPEWIRE:=auto}"
: "${FEDORA_DEVKIT_PIPEWIRE_CONFIG:=/etc/fedora-shell/pipewire-devkit.conf}"
: "${FEDORA_DEVKIT_DEBUG:=0}"
: "${FEDORA_TERMUX_X11_LEGACY_DRAWING:=1}"
: "${FEDORA_TERMUX_X11_FORCE_BGRA:=0}"
: "${FEDORA_TERMUX_X11_AUTO_OPEN:=auto}"
: "${FEDORA_INSTALL_ROOT:=$FEDORA_USER_HOME/.local/share/fedora-shell}"
: "${FEDORA_SHARED_STORAGE:=$FEDORA_USER_HOME/storage/shared}"
: "${FEDORA_GUEST_PROJECT_ROOT:=/opt/fedora-shell}"
: "${FEDORA_ANDROID_ALLOWLIST_FILE:=$FEDORA_INSTALL_ROOT/config/android-memory-allowlist.json}"

if [[ ! "$FEDORA_CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
  printf '[fedora-shell][error] Refusing an unsafe container name: %s\n' \
    "$FEDORA_CONTAINER" >&2
  return 1 2>/dev/null || exit 64
fi

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
  config
  fedora
  gpu
  audio
  input
  integration
  README.md
  AUDIT.md
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
FEDORA_STATE_RECORD_DIR="${FEDORA_STATE_DIR}/state"
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

fedora_prepare_directories() {
  local directory

  for directory in "$@"; do
    fedora_path_is_safe "$directory" || return 1
    if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
      printf '[fedora-shell][error] Refusing an unsafe directory target: %s\n' "$directory" >&2
      return 1
    fi
  done

  mkdir -p "$@" || return 1

  for directory in "$@"; do
    if [[ ! -d "$directory" || -L "$directory" ]]; then
      printf '[fedora-shell][error] Directory became unsafe after creation: %s\n' "$directory" >&2
      return 1
    fi
  done
}

fedora_atomic_write() {
  local destination="$1"
  local mode="${2:-600}"
  local parent temporary

  # State/PID files are control-plane inputs. Write them in the same
  # directory and rename them into place so an interrupted command cannot
  # leave a truncated record that a later start/stop operation trusts.
  fedora_path_is_safe "$destination" || return 1
  if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
    printf '[fedora-shell][error] Refusing an unsafe atomic-write target: %s\n' \
      "$destination" >&2
    return 1
  fi
  parent="${destination%/*}"
  [[ -n "$parent" ]] || parent="/"
  [[ -d "$parent" && ! -L "$parent" ]] || return 1

  temporary="$(mktemp "$parent/.fedora-shell-write.XXXXXX")" || return 1
  if ! cat > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod "$mode" "$temporary" 2>/dev/null || {
    rm -f -- "$temporary"
    return 1
  }
  [[ ! -L "$destination" ]] || {
    rm -f -- "$temporary"
    printf '[fedora-shell][error] Atomic-write target became a symlink: %s\n' \
      "$destination" >&2
    return 1
  }
  mv -f -- "$temporary" "$destination"
  [[ -f "$destination" && ! -L "$destination" ]] || return 1
  chmod "$mode" "$destination" 2>/dev/null || true
}

# Report files are user-visible output, but they are still written from
# control paths and may contain device identifiers. Keep the destination
# absolute, reject symlinks/non-regular files, and require a real parent before
# any caller redirects output into it.
fedora_report_path_is_safe() {
  local path="$1"
  local parent

  fedora_path_is_safe "$path" || return 1
  parent="${path%/*}"
  [[ -n "$parent" ]] || parent="/"
  [[ -d "$parent" && ! -L "$parent" ]] || return 1
  [[ ! -L "$path" && ( ! -e "$path" || -f "$path" ) ]] || return 1
}

fedora_have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

fedora_require_cmd() {
  fedora_have_cmd "$1" || fedora_die "Required command not found: $1"
}

fedora_termux_full_upgrade() {
  # Termux is a rolling release. Keep the whole shared-library set in one
  # transaction and preserve user-edited config files without opening a dpkg
  # question in the middle of an installer/Widget run.
  if fedora_have_cmd apt-get; then
    DEBIAN_FRONTEND=noninteractive apt-get \
      -o Dpkg::Options::=--force-confold \
      -y dist-upgrade
  else
    pkg upgrade -y
  fi
}

fedora_repair_project_modes() {
  local project_root="$1"
  local executable_path
  local -a executable_paths=(
    "$project_root"/scripts/*.sh
    "$project_root"/scripts/lib/*.sh
    "$project_root"/gpu/scripts/*.sh
    "$project_root"/audio/*.sh
    "$project_root"/input/*.sh
    "$project_root"/integration/*.sh
    "$project_root"/integration/widget/*
    "$project_root"/fedora/rootfs/*.sh
    "$project_root"/fedora/gnome/fedora-session
    "$project_root"/fedora/gnome/fedora-run
    "$project_root"/fedora/gnome/mutter-devkit-wrapper
    "$project_root"/fedora/rootfs/restore-mutter-devkit.sh
    "$project_root"/fedora/gnome/install-integration.sh
    "$project_root"/tests/static.sh
  )

  [[ -d "$project_root" ]] || {
    fedora_die "Project root is missing: $project_root"
    return 1
  }
  # Some Android/Git combinations have historically checked out executable
  # files as 0644. These are project-owned launchers; restoring 0755 here is
  # safe and makes an update self-healing before the tree is copied elsewhere.
  for executable_path in "${executable_paths[@]}"; do
    if [[ -f "$executable_path" && ! -L "$executable_path" ]]; then
      chmod 0755 "$executable_path"
    fi
  done
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
  local cmd_bin=/system/bin/cmd
  local output=""
  local confirmed_absent=0
  local query_unknown=0

  # A visible pm/cmd executable is not enough evidence on Android 16: the
  # package query can be denied for the Termux UID. Distinguish confirmed
  # absence from an unreadable query so callers never mistake a restricted
  # API for an uninstalled APK.
  if [[ -x "$pm_bin" ]]; then
    if output="$("$pm_bin" path "$package_name" 2>&1)"; then
      if grep -Eq '^package:[^[:space:]]+([[:space:]]|$)' <<< "$output"; then
        return 0
      elif grep -Eiq 'package.*(not found|does not exist)|unable to find package|unknown package' <<< "$output"; then
        confirmed_absent=1
      else
        query_unknown=1
      fi
    elif grep -Eiq 'package.*(not found|does not exist)|unable to find package|unknown package' <<< "$output"; then
      confirmed_absent=1
    else
      query_unknown=1
    fi
  fi

  # Android 16/vendor builds can expose pm but restrict its package query to
  # the shell UID. Try the read-only cmd package path equivalent before
  # reporting that an optional APK is absent.
  if [[ -x "$cmd_bin" ]]; then
    if output="$("$cmd_bin" package path "$package_name" 2>&1)"; then
      if grep -Eq '^package:[^[:space:]]+([[:space:]]|$)' <<< "$output"; then
        return 0
      elif grep -Eiq 'package.*(not found|does not exist)|unable to find package|unknown package' <<< "$output"; then
        confirmed_absent=1
      else
        query_unknown=1
      fi
    elif grep -Eiq 'package.*(not found|does not exist)|unable to find package|unknown package' <<< "$output"; then
      confirmed_absent=1
    else
      query_unknown=1
    fi
  fi

  (( query_unknown )) && return 2
  (( confirmed_absent )) && return 1
  return 2
}

fedora_init_state() {
  umask 077
  fedora_user_data_path_is_safe "$FEDORA_STATE_DIR" || {
    printf '[fedora-shell][error] State directory must be a safe child of the Termux home and outside the checkout: %s\n' \
      "$FEDORA_STATE_DIR" >&2
    return 1
  }
  fedora_prepare_directories \
    "$FEDORA_STATE_DIR" \
    "$FEDORA_LOG_DIR" \
    "$FEDORA_PID_DIR" \
    "$FEDORA_STATE_RECORD_DIR" || return 1
  chmod 700 "$FEDORA_STATE_DIR" "$FEDORA_LOG_DIR" "$FEDORA_PID_DIR" \
    "$FEDORA_STATE_RECORD_DIR" 2>/dev/null || true
}

fedora_init_log() {
  fedora_init_state || return 1
  FEDORA_LOG_FILE="${FEDORA_LOG_FILE:-$FEDORA_LOG_DIR/$(basename "$0").log}"
  export FEDORA_LOG_FILE

  fedora_path_is_safe "$FEDORA_LOG_FILE" || return 1
  if [[ -e "$FEDORA_LOG_FILE" && ( -L "$FEDORA_LOG_FILE" || ! -f "$FEDORA_LOG_FILE" ) ]]; then
    printf '[fedora-shell][error] Refusing an unsafe log file: %s\n' "$FEDORA_LOG_FILE" >&2
    return 1
  fi

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
  if ! FEDORA_PD_BIN="$(fedora_pd_bin)"; then
    fedora_die "proot-distro is not installed. Run install.sh first."
    return 1
  fi
  export FEDORA_PD_BIN
}

fedora_container_exists() {
  local pd_bin="${FEDORA_PD_BIN:-$(fedora_pd_bin 2>/dev/null || true)}"
  [[ -n "$pd_bin" ]] || return 1
  "$pd_bin" list --quiet 2>/dev/null | grep -Fxq "$FEDORA_CONTAINER"
}

fedora_require_container() {
  fedora_require_pd || return 1
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
  [[ -f "$source" && ! -L "$source" ]] || {
    fedora_die "Missing or symlinked project file: $source"
    return 1
  }
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
  fedora_require_pd || return 1
  if ! fedora_install_root_path_is_safe "$FEDORA_INSTALL_ROOT"; then
    fedora_die "Refusing an unsafe Fedora installation bind source: $FEDORA_INSTALL_ROOT"
    return 1
  fi
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

  [[ -d "$source_root" && ! -L "$source_root" ]] || {
    fedora_die "Project checkout does not exist: $source_root"
    return 1
  }
  [[ "$source_root" != "$target_root" ]] || return 0
  fedora_path_is_safe "$target_root" || return 1
  fedora_user_data_path_is_safe "$target_root" || {
    fedora_die "Refusing to synchronize outside the safe user-data tree: $target_root"
    return 1
  }
  [[ ! -L "$target_root" ]] || {
    fedora_die "Refusing to synchronize into symlinked installation root: $target_root"
    return 1
  }
  fedora_prepare_directories "$target_root" || return 1
  [[ -d "$target_root" && ! -L "$target_root" ]] || {
    fedora_die "Installation root is not a real directory: $target_root"
    return 1
  }
  for item in "${FEDORA_PROJECT_ITEMS[@]}"; do
    [[ -e "$source_root/$item" ]] || {
      fedora_die "Project file is missing: $source_root/$item"
      return 1
    }
    [[ ! -L "$source_root/$item" ]] || {
      fedora_die "Refusing to synchronize a symlinked project item: $source_root/$item"
      return 1
    }
    [[ ! -L "$target_root/$item" ]] || {
      fedora_die "Refusing to overwrite a symlinked installed project item: $target_root/$item"
      return 1
    }
    # cp -a preserves links, but a later guest bind or package helper could
    # follow one.  Fail closed for the complete project item, not just its
    # top-level entry, so a compromised checkout cannot redirect the control
    # tree outside the intended installation root.
    if find "$source_root/$item" -type l -print -quit 2>/dev/null | grep -q .; then
      fedora_die "Refusing to synchronize a project item containing symlinks: $source_root/$item"
      return 1
    fi
    if [[ -e "$target_root/$item" ]] \
      && find "$target_root/$item" -type l -print -quit 2>/dev/null | grep -q .; then
      fedora_die "Refusing to overwrite an installed project item containing symlinks: $target_root/$item"
      return 1
    fi
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
  fedora_path_is_safe "$pid_file" || return 1
  if [[ -L "$pid_file" ]]; then
    fedora_warn "Refusing to follow symlinked project PID file: $pid_file"
    return 1
  fi
  if [[ -e "$pid_file" && ! -f "$pid_file" ]]; then
    fedora_warn "Refusing non-regular project PID file: $pid_file"
    return 1
  fi
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

fedora_stop_owned_transports() {
  # Cleanup for recovery/destructive commands when the installed stop helper
  # is unavailable. Every target is identified by Fedora Shell's own PID file
  # and command-line marker; Android processes are never searched or touched.
  fedora_kill_owned_pid "$FEDORA_PID_DIR/android-bridge-broker.pid" android-bridge-broker.sh
  fedora_kill_owned_pid "$FEDORA_PID_DIR/virgl.pid" virgl_test_server_android
  fedora_kill_owned_pid "$FEDORA_PID_DIR/termux-x11.pid" termux-x11
  rm -f -- "$FEDORA_PID_DIR/termux-x11.args"
  local audio_stop="$FEDORA_INSTALL_ROOT/audio/stop.sh"
  if [[ -x "$audio_stop" && ! -L "$audio_stop" ]]; then
    "$audio_stop" || fedora_warn "Could not stop the project-owned audio transport."
  fi
}

fedora_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

fedora_keyboard_mode_valid() {
  case "${1:-}" in
    linux|focused|auto) return 0 ;;
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
  local target_dir temporary
  if [[ ! -f "$source" || -L "$source" ]]; then
    fedora_die "Refusing to install a missing or symlinked source file: $source"
    return 1
  fi
  if [[ -L "$target" ]]; then
    fedora_die "Refusing to overwrite symlink: $target"
    return 1
  fi
  if [[ -e "$target" ]] && ! grep -Fq -- "$marker" "$target" 2>/dev/null; then
    fedora_die "Refusing to overwrite non-project file: $target"
    return 1
  fi
  fedora_path_is_safe "$target" || return 1
  target_dir="$(dirname -- "$target")"
  fedora_prepare_directories "$target_dir" || return 1
  temporary="$(mktemp "$target_dir/.fedora-shell-owned.XXXXXX")" || return 1
  if ! cp -- "$source" "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  if ! chmod 700 "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  [[ ! -L "$target" ]] || {
    rm -f -- "$temporary"
    fedora_die "Target became a symlink during installation: $target"
    return 1
  }
  mv -f -- "$temporary" "$target"
  [[ -f "$target" && ! -L "$target" ]] || return 1
  chmod 700 "$target" 2>/dev/null || true
}

fedora_remove_owned_file() {
  local target="$1"
  local marker="$2"
  [[ -e "$target" || -L "$target" ]] || return 0
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
