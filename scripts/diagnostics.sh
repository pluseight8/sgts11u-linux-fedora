#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-diagnostics-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"

MODE=quick
INCLUDE_FEDORA=1
FRAME_PACING=0
REDACT=0

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/diagnostics.sh [OPTIONS]

Options:
  --quick             collect a small local report (default)
  --full              include Android display/input/audio and Termux inventory
  --fedora            include Fedora guest probes
  --no-fedora         skip guest probes
  --frame-pacing      append the frame-pacing proxy report
  --redact            redact common identifiers and private paths before sharing
  -h, --help          show this help
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --quick) MODE=quick; shift ;;
    --full) MODE=full; shift ;;
    --fedora) INCLUDE_FEDORA=1; shift ;;
    --no-fedora) INCLUDE_FEDORA=0; shift ;;
    --frame-pacing) FRAME_PACING=1; shift ;;
    --redact) REDACT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fedora_die "Unknown option: $1"; exit 64 ;;
  esac
done

fedora_require_termux
fedora_require_non_root
fedora_init_state
report="$FEDORA_LOG_DIR/diagnostics-$(date -u +%Y%m%dT%H%M%SZ).txt"
umask 077

capture() {
  local label="$1"
  shift
  {
    printf '\n[%s]\n' "$label"
    if "$@"; then
      printf '[exit=0]\n'
    else
      local rc=$?
      printf '[exit=%s]\n' "$rc"
    fi
  } >> "$report" 2>&1
}

android_setting() {
  local namespace="$1"
  local key="$2"
  if [[ -x /system/bin/settings ]]; then
    /system/bin/settings get "$namespace" "$key" 2>/dev/null || true
  else
    printf '%s\n' unknown
  fi
}

android_package_state() {
  local package_name="$1"
  local package_rc
  if fedora_android_package_installed "$package_name"; then
    printf '%s\n' yes
  else
    package_rc=$?
    if (( package_rc == 2 )); then
      printf '%s\n' unknown
    else
      printf '%s\n' no
    fi
  fi
}

process_memory_snapshot() {
  command -v ps >/dev/null 2>&1 || return 1
  # RSS is useful for pressure triage but double-counts shared libraries.
  # Include PSS from smaps_rollup when Android permits it, so the report also
  # has a closer estimate of the memory attributed to each process.
  local count=0 total_rss=0 total_pss=0 pid rss args pss
  while read -r pid rss args; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    case "$args" in
      *gnome-shell*|*mutter-devkit*|*ptyxis*|*gnome-console*|*gnome-settings-daemon*|*pipewire*|*wireplumber*|*xdg-desktop-portal*|*localsearch*|*tracker*|*goa*|*evolution*|*calendar-server*) ;;
      *) continue ;;
    esac
    pss="$(awk '/^Pss:/ { print $2; exit }' "/proc/$pid/smaps_rollup" 2>/dev/null || true)"
    [[ "$pss" =~ ^[0-9]+$ ]] || pss=unknown
    printf 'pid=%s rss_kib=%s pss_kib=%s cmd=%s\n' "$pid" "$rss" "$pss" "$args"
    total_rss=$((total_rss + rss))
    if [[ "$pss" =~ ^[0-9]+$ ]]; then
      total_pss=$((total_pss + pss))
    fi
    count=$((count + 1))
  done < <(ps -eo pid=,rss=,args= 2>/dev/null)
  printf 'matched_processes=%d total_rss_kib=%d total_pss_kib=%d\n' \
    "$count" "$total_rss" "$total_pss"
}

termux_x11_inventory() {
  printf 'termux_x11_command=%s\n' "$(command -v termux-x11 2>/dev/null || echo missing)"
  if command -v dpkg-query >/dev/null 2>&1; then
    printf 'termux_x11_package_version='
    dpkg-query -W -f='${Version}\n' termux-x11-nightly 2>/dev/null || printf '%s\n' unknown
  fi
  if [[ -x /system/bin/pm ]]; then
    printf 'android_package_uids=\n'
    /system/bin/pm list packages -U 2>/dev/null \
      | grep -E 'com\.termux($|\.x11)' || true
    printf 'android_x11_package_summary=\n'
    /system/bin/dumpsys package com.termux.x11 2>/dev/null \
      | awk '/Package \[com\.termux\.x11\]|versionName=|versionCode=|userId=|codePath=/{print}' \
      | head -n 20 || true
  else
    printf 'android_package_uids=unknown\n'
    printf 'android_x11_package_summary=unknown\n'
  fi
}

guest_runtime_evidence() {
  local runtime="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime"
  local path
  printf 'runtime_path=%s\n' "$runtime"
  if [[ ! -d "$runtime" ]]; then
    printf '%s\n' 'runtime=missing'
    return 0
  fi
  printf 'runtime_entries=\n'
  while IFS= read -r path; do
    printf '%s type=%s\n' "$(basename -- "$path")" \
      "$(stat -c %F "$path" 2>/dev/null || printf unknown)"
  done < <(find "$runtime" -maxdepth 1 \( -type s -o -type f \) -print 2>/dev/null | sort)
  printf 'wayland_socket=%s\n' \
    "$(find "$runtime" -maxdepth 1 -type s -name 'wayland-*' -print -quit 2>/dev/null | sed 's#^.*/##' || true)"
  if [[ -S "$runtime/pipewire-0" ]]; then
    printf '%s\n' 'pipewire_main_socket=present'
  else
    printf '%s\n' 'pipewire_main_socket=absent'
  fi
  if [[ -S "$runtime/pipewire-0-manager" ]]; then
    printf '%s\n' 'pipewire_manager_socket=present'
  else
    printf '%s\n' 'pipewire_manager_socket=absent'
  fi
  if [[ -r "$runtime/pipewire.pid" ]]; then
    printf 'pipewire_pid=%s\n' "$(sed -n '1p' "$runtime/pipewire.pid" 2>/dev/null || true)"
  else
    printf '%s\n' 'pipewire_pid=missing'
  fi
}

guest_session_log_evidence() {
  local session_log="$FEDORA_TERMUX_PREFIX/tmp/fedora-session.log"
  printf 'session_log_path=%s\n' "$session_log"
  if [[ -r "$session_log" ]]; then
    printf '%s\n' 'session_log_tail_begin='
    tail -n 220 "$session_log"
    printf '%s\n' 'session_log_tail_end='
  else
    printf '%s\n' 'session_log=missing'
  fi
}

guest_process_evidence() {
  if ! fedora_container_running; then
    printf '%s\n' 'guest_container=not-running'
    return 0
  fi
  printf '%s\n' 'guest_container=running'
  # shellcheck disable=SC2016
  fedora_pd_login /usr/bin/env \
    "XDG_RUNTIME_DIR=/tmp/fedora-runtime" \
    /bin/bash -c '
      printf "%s\n" "guest_processes="
      ps -eo pid=,stat=,comm=,args= 2>/dev/null \
        | grep -E "gnome-shell|mutter-devkit|pipewire|wireplumber|xdg-desktop-portal|goa|evolution|calendar-server" \
        || true
      printf "%s\n" "devkit_pipewire_config="
      if [[ -r /etc/fedora-shell/pipewire-devkit.conf ]]; then
        printf "%s\n" "present"
      else
        printf "%s\n" "missing"
      fi
      printf "%s\n" "pipewire_client_probe="
      XDG_RUNTIME_DIR=/tmp/fedora-runtime \
      PIPEWIRE_RUNTIME_DIR=/tmp/fedora-runtime \
      PIPEWIRE_REMOTE=pipewire-0 \
      PIPEWIRE_CORE=pipewire-0 \
        pw-cli -r pipewire-0 info 0 2>&1 || true
    '
}

selinux_state="unknown"
if fedora_have_cmd getenforce; then
  selinux_state="$(getenforce 2>/dev/null || true)"
elif [[ -r /sys/fs/selinux/enforce ]]; then
  selinux_state="$(< /sys/fs/selinux/enforce)"
fi
x11_socket="$FEDORA_TERMUX_PREFIX/tmp/.X11-unix/X${FEDORA_DISPLAY#:}"
x11_pid=""
if [[ -f "$FEDORA_PID_DIR/termux-x11.pid" ]]; then
  x11_pid="$(sed -n '1p' "$FEDORA_PID_DIR/termux-x11.pid" 2>/dev/null || true)"
fi
virgl_installed=no
if fedora_have_cmd virgl_test_server_android; then
  virgl_installed=yes
fi

{
  printf 'fedora-shell-diagnostics-v1\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'mode=%s\n' "$MODE"
  printf 'termux_version=%s\n' "${TERMUX_VERSION:-unknown}"
  printf 'uname=%s\n' "$(uname -a 2>/dev/null || true)"
  printf 'uname_m=%s\n' "$(uname -m 2>/dev/null || true)"
  printf 'manufacturer=%s\n' "$(fedora_getprop ro.product.manufacturer)"
  printf 'model=%s\n' "$(fedora_getprop ro.product.model)"
  printf 'device_codename=%s\n' "$(fedora_getprop ro.product.device)"
  printf 'android_release=%s\n' "$(fedora_getprop ro.build.version.release)"
  printf 'android_api=%s\n' "$(fedora_getprop ro.build.version.sdk)"
  printf 'security_patch=%s\n' "$(fedora_getprop ro.build.version.security_patch)"
  printf 'board=%s\n' "$(fedora_getprop ro.board.platform)"
  printf 'hardware=%s\n' "$(fedora_getprop ro.hardware)"
  printf 'soc_model=%s\n' "$(fedora_getprop ro.soc.model)"
  printf 'kernel_release=%s\n' "$(uname -r 2>/dev/null || true)"
  printf 'ram_kib=%s\n' "$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null || true)"
  printf 'memory_profile=%s\n' "$FEDORA_MEMORY_PROFILE"
  printf 'settings_daemon=%s\n' "$FEDORA_SETTINGS_DAEMON"
  printf 'launch_terminal=%s\n' "$FEDORA_LAUNCH_TERMINAL"
  printf 'keyring_mode=%s\n' "$FEDORA_KEYRING_MODE"
  printf 'search_mode=%s\n' "$FEDORA_SEARCH_MODE"
  printf 'calendar_mode=%s\n' "$FEDORA_CALENDAR_MODE"
  printf 'selinux=%s\n' "$selinux_state"
  printf 'display=%s\n' "$FEDORA_DISPLAY"
  printf 'peak_refresh_rate=%s\n' "$(android_setting system peak_refresh_rate)"
  printf 'min_refresh_rate=%s\n' "$(android_setting system min_refresh_rate)"
  printf 'termux_x11_package=%s\n' "$(fedora_have_cmd termux-x11 && echo yes || echo no)"
  printf 'termux_x11_apk=%s\n' "$(android_package_state com.termux.x11)"
  printf 'termux_x11_socket=%s\n' "$( [[ -S "$x11_socket" ]] && echo present || echo absent )"
  printf 'termux_x11_pid=%s\n' "${x11_pid:-unknown}"
  printf 'termux_x11_auto_open=%s\n' "$FEDORA_TERMUX_X11_AUTO_OPEN"
  printf 'termux_x11_legacy_drawing=%s\n' "$FEDORA_TERMUX_X11_LEGACY_DRAWING"
  printf 'termux_x11_force_bgra=%s\n' "$FEDORA_TERMUX_X11_FORCE_BGRA"
  printf 'virgl_server=%s\n' "$virgl_installed"
  printf 'gpu_mode=%s\n' "$FEDORA_GPU_MODE"
  printf 'portal_mode=%s\n' "$FEDORA_PORTAL_MODE"
  printf 'nested_xwayland=%s\n' "$FEDORA_NESTED_XWAYLAND"
  printf 'devkit_gdk_backend=%s\n' "$FEDORA_DEVKIT_GDK_BACKEND"
  printf 'devkit_pipewire=%s\n' "$FEDORA_DEVKIT_PIPEWIRE"
  printf 'devkit_pipewire_config=%s\n' "$FEDORA_DEVKIT_PIPEWIRE_CONFIG"
  printf 'redacted=%s\n' "$([[ $REDACT -eq 1 ]] && echo yes || echo no)"
  printf 'state_dir=%s\n' "$FEDORA_STATE_DIR"
  printf 'install_root=%s\n' "$FEDORA_INSTALL_ROOT"
  printf 'container=%s\n' "$FEDORA_CONTAINER"
  printf 'container_installed=%s\n' "$(fedora_container_exists && echo yes || echo no)"
  printf 'container_running=%s\n' "$(fedora_container_running && echo yes || echo no)"
} > "$report"

capture 'free space' df -Pk "$FEDORA_USER_HOME"
if [[ -x /system/bin/getprop ]]; then
  capture 'selected Android properties' /system/bin/getprop ro.product.model
fi
if fedora_have_cmd termux-x11; then
  capture 'Termux:X11 process package' termux-x11 --help
fi

if [[ "$MODE" == full ]]; then
  if [[ -x /system/bin/getprop ]]; then
    capture 'Android getprop' /system/bin/getprop || true
  fi
  capture 'CPU info' cat /proc/cpuinfo
  capture 'memory info' cat /proc/meminfo
  capture 'Termux info' termux-info
  capture 'installed Termux packages' pkg list-installed
  capture 'Termux:X11 preferences' termux-x11-preference list
  capture 'host process RSS snapshot' process_memory_snapshot
  if [[ -x /system/bin/dumpsys ]]; then
    capture 'Android display' /system/bin/dumpsys display || true
    capture 'SurfaceFlinger' /system/bin/dumpsys SurfaceFlinger || true
    capture 'Android input' /system/bin/dumpsys input || true
    capture 'Android audio' /system/bin/dumpsys audio || true
  fi
  capture 'Termux:X11 package inventory' termux_x11_inventory
  capture 'Fedora runtime sockets' guest_runtime_evidence
  capture 'Fedora session log tail' guest_session_log_evidence
  capture 'Fedora guest processes' guest_process_evidence
else
  if [[ -x /system/bin/settings ]]; then
    capture 'Android display settings' /system/bin/settings get system peak_refresh_rate || true
    capture 'Android min refresh setting' /system/bin/settings get system min_refresh_rate || true
  fi
fi

if (( INCLUDE_FEDORA )); then
  if fedora_container_exists; then
    {
      printf '\n[Fedora guest probes]\n'
      fedora_pd_login /usr/bin/env \
        "DISPLAY=$FEDORA_DISPLAY" \
        "XDG_RUNTIME_DIR=/tmp/fedora-runtime" \
        "FEDORA_GPU_MODE=$FEDORA_GPU_MODE" \
        /usr/local/bin/fedora-gpu-check
    } >> "$report" 2>&1 || true
    {
      printf '\n[Fedora guest version]\n'
      # shellcheck disable=SC2016
      fedora_pd_login /usr/bin/env \
        "DISPLAY=$FEDORA_DISPLAY" \
        "XDG_RUNTIME_DIR=/tmp/fedora-runtime" \
        /bin/bash -c 'cat /etc/fedora-release 2>/dev/null || true; gnome-shell --version 2>/dev/null || true; mutter --version 2>/dev/null || true; printf "session=%s wayland=%s\n" "${XDG_SESSION_TYPE:-}" "${WAYLAND_DISPLAY:-}"'
    } >> "$report" 2>&1 || true
  else
    printf '\n[Fedora guest probes]\ncontainer not installed; skipped\n' >> "$report"
  fi
fi

if (( FRAME_PACING )); then
  if [[ -x "$FEDORA_INSTALL_ROOT/gpu/scripts/measure-frame-pacing.sh" ]]; then
    "$FEDORA_INSTALL_ROOT/gpu/scripts/measure-frame-pacing.sh" >> "$report" 2>&1 || true
  else
    printf '\n[frame pacing]\ninstalled frame-pacing script is missing\n' >> "$report"
  fi
fi

if (( REDACT )); then
  redacted_report="${report}.redacted.$$"
  if sed -E \
    -e 's#(/data/data/[^[:space:]]+)#<termux-private-path>#g' \
    -e 's#(/home/[^[:space:]]+)#<home-path>#g' \
    -e 's#(\[?[^]]*(serial(no)?|imei|imsi|meid|ssid|bssid)[^]]*\]?[[:space:]]*[:=][[:space:]]*)[^[:space:]]+#\1<redacted>#Ig' \
    -e 's#((serial(no)?|imei|imsi|meid|ssid|bssid|android_id)[^:=]*[=:][[:space:]]*)[^[:space:]]+#\1<redacted>#Ig' \
    "$report" > "$redacted_report"; then
    mv -- "$redacted_report" "$report"
  else
    rm -f -- "$redacted_report"
    fedora_warn "Could not create the redacted report; keep the full report private."
  fi
fi

chmod 600 "$report"
printf 'report=%s\n' "$report"
if (( REDACT )); then
  printf '%s\n' 'Report was redacted with best-effort filters; inspect it once before sharing.'
else
  printf '%s\n' 'Use --redact before sharing; a full report may contain serial/IMEI/SSID/private paths.'
fi
