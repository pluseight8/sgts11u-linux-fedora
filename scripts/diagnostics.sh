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
report="$FEDORA_LOG_DIR/diagnostics-$(date -u +%Y%m%dT%H%M%SZ)-$$.txt"
fedora_report_path_is_safe "$report" || {
  fedora_die "Refusing an unsafe diagnostics report path: $report"
  exit 1
}
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

readonly_sysfs_bytes_to_kib() {
  local path="$1"
  local raw=""
  [[ -r "$path" ]] || return 0
  raw="$(sed -nE 's/^[[:space:]]*([0-9]+)[[:space:]]*$/\1/p' "$path" 2>/dev/null \
    | sed -n '1p' || true)"
  [[ "$raw" =~ ^[0-9]+$ ]] || return 0
  printf '%s\n' "$(((raw + 1023) / 1024))"
}

android_ramplus_snapshot() {
  # Samsung RAM Plus is an OEM Android setting backed by Android's own memory
  # policy. Unprivileged Termux cannot reliably read its UI value, and this
  # probe must never write settings, resize swap or change kernel state. Report
  # only indirect swap/zRAM evidence and keep the setting explicitly unknown.
  local device size used swap_type
  local swap_entries=0 zram_swap_entries=0 swap_total=0 swap_used=0
  local zram_device_count=0 zram_path configured original compressed physical
  local configured_total=0 original_total=0 compressed_total=0 physical_total=0
  local configured_seen=0 original_seen=0 compressed_seen=0 physical_seen=0

  printf '%s\n' 'ramplus_setting=not-readable'
  printf '%s\n' 'ramplus_control=Android/Samsung only; no Fedora-side mutation'

  if [[ -r /proc/swaps ]]; then
    while read -r device _ size used swap_type; do
      [[ "$size" =~ ^[0-9]+$ && "$used" =~ ^[0-9]+$ ]] || continue
      swap_entries=$((swap_entries + 1))
      swap_total=$((swap_total + size))
      swap_used=$((swap_used + used))
      if [[ "$device" == *zram* ]]; then
        zram_swap_entries=$((zram_swap_entries + 1))
      fi
    done < <(tail -n +2 /proc/swaps 2>/dev/null || true)
    printf 'swap_probe=readable swap_entries=%d zram_swap_entries=%d swap_total_kib=%d swap_used_kib=%d\n' \
      "$swap_entries" "$zram_swap_entries" "$swap_total" "$swap_used"
    printf 'non_zram_swap_entries=%d\n' "$((swap_entries - zram_swap_entries))"
  else
    printf '%s\n' 'swap_probe=unavailable'
    printf '%s\n' 'non_zram_swap_entries=unknown'
  fi

  for zram_path in /sys/block/zram[0-9]*; do
    [[ -d "$zram_path" ]] || continue
    zram_device_count=$((zram_device_count + 1))
    configured="$(readonly_sysfs_bytes_to_kib "$zram_path/disksize")"
    original="$(readonly_sysfs_bytes_to_kib "$zram_path/orig_data_size")"
    compressed="$(readonly_sysfs_bytes_to_kib "$zram_path/compr_data_size")"
    physical="$(readonly_sysfs_bytes_to_kib "$zram_path/mem_used_total")"
    [[ "$configured" =~ ^[0-9]+$ ]] && {
      configured_total=$((configured_total + configured)); configured_seen=1;
    }
    [[ "$original" =~ ^[0-9]+$ ]] && {
      original_total=$((original_total + original)); original_seen=1;
    }
    [[ "$compressed" =~ ^[0-9]+$ ]] && {
      compressed_total=$((compressed_total + compressed)); compressed_seen=1;
    }
    [[ "$physical" =~ ^[0-9]+$ ]] && {
      physical_total=$((physical_total + physical)); physical_seen=1;
    }
    printf 'zram_device=%s disksize_kib=%s orig_data_kib=%s compr_data_kib=%s physical_used_kib=%s\n' \
      "${zram_path##*/}" "${configured:-unknown}" "${original:-unknown}" \
      "${compressed:-unknown}" "${physical:-unknown}"
  done

  if (( zram_device_count > 0 )); then
    printf 'zram_probe=visible zram_device_count=%d\n' "$zram_device_count"
  else
    printf '%s\n' 'zram_probe=not-visible'
  fi
  (( configured_seen )) && printf 'zram_configured_total_kib=%d\n' "$configured_total" \
    || printf '%s\n' 'zram_configured_total_kib=unknown'
  (( original_seen )) && printf 'zram_original_data_total_kib=%d\n' "$original_total" \
    || printf '%s\n' 'zram_original_data_total_kib=unknown'
  (( compressed_seen )) && printf 'zram_compressed_data_total_kib=%d\n' "$compressed_total" \
    || printf '%s\n' 'zram_compressed_data_total_kib=unknown'
  (( physical_seen )) && printf 'zram_physical_used_total_kib=%d\n' "$physical_total" \
    || printf '%s\n' 'zram_physical_used_total_kib=unknown'
  printf '%s\n' 'ramplus_note=zRAM/swap observations are indirect and do not prove the Samsung RAM Plus UI state or amount'
}

devkit_viewer_environment() {
  command -v ps >/dev/null 2>&1 || return 1
  local pid comm command_line environment
  while read -r pid comm command_line; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    if [[ "$comm" != mutter-devkit ]]; then
      # The Fedora-only activation shim is a script. Depending on the kernel
      # and procps build, ps may expose it as `bash`/`env` instead of the
      # target basename. Match only the two project-owned Mutter paths and do
      # not print the command line, which can contain private arguments.
      case "$command_line" in
        */usr/libexec/mutter-devkit*|*mutter-devkit.real*) ;;
        *) continue ;;
      esac
    fi
    if [[ -r "/proc/$pid/environ" ]]; then
      environment="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
        | grep -E '^(DISPLAY|GDK_BACKEND|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|PIPEWIRE_RUNTIME_DIR|PIPEWIRE_REMOTE|PIPEWIRE_CORE)=' \
        | tr '\n' ' ' || true)"
    else
      environment=unavailable
    fi
    printf 'pid=%s comm=%s env=%s\n' "$pid" "$comm" "${environment:-unavailable}"
  done < <(ps -eo pid=,comm=,args= 2>/dev/null)
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

android_app_bridge_evidence() {
  local runtime="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/android-bridge"
  local pid_file="$FEDORA_PID_DIR/android-bridge-broker.pid"
  local broker_pid=""
  printf 'android_apps_mode=%s\n' "$FEDORA_ANDROID_APPS_MODE"
  printf 'broker_runtime=%s\n' "$runtime"
  if [[ -d "$runtime/requests" && -d "$runtime/responses" ]]; then
    printf '%s\n' 'broker_queue=present'
  else
    printf '%s\n' 'broker_queue=absent'
  fi
  if [[ -r "$pid_file" ]]; then
    broker_pid="$(sed -n '1p' "$pid_file" 2>/dev/null || true)"
    printf 'broker_pid=%s\n' "${broker_pid:-unknown}"
    if fedora_pid_matches "$broker_pid" android-bridge-broker.sh; then
      printf '%s\n' 'broker_process=alive'
    else
      printf '%s\n' 'broker_process=not-owned-or-dead'
    fi
  else
    printf '%s\n' 'broker_pid=missing'
    printf '%s\n' 'broker_process=not-running'
  fi
  if [[ -x "$FEDORA_INSTALL_ROOT/integration/android-bridge.sh" ]]; then
    printf '%s\n' 'bridge_client=present'
  else
    printf '%s\n' 'bridge_client=missing'
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
      printf "%s\n" "mutter_devkit_target="
      if [[ -f /usr/libexec/mutter-devkit && ! -L /usr/libexec/mutter-devkit ]] \
        && grep -Fq "fedora-shell-mutter-devkit-wrapper-v1" /usr/libexec/mutter-devkit 2>/dev/null; then
        printf "%s\n" "fedora-shell-wrapper"
      elif [[ -x /usr/libexec/mutter-devkit && ! -L /usr/libexec/mutter-devkit ]]; then
        printf "%s\n" "rpm-or-unmanaged-binary"
      elif [[ -L /usr/libexec/mutter-devkit ]]; then
        printf "%s\n" "symlink-preserved"
      else
        printf "%s\n" "missing"
      fi
      printf "%s\n" "mutter_devkit_original="
      if [[ -x /usr/local/libexec/fedora-shell/mutter-devkit.real \
        && ! -L /usr/local/libexec/fedora-shell/mutter-devkit.real \
        && -f /usr/local/libexec/fedora-shell/mutter-devkit.real.owner \
        && ! -L /usr/local/libexec/fedora-shell/mutter-devkit.real.owner ]] \
        && grep -Fq "fedora-shell-mutter-devkit-real-v1" \
          /usr/local/libexec/fedora-shell/mutter-devkit.real.owner 2>/dev/null; then
        printf "%s\n" "saved-and-owned"
      else
        printf "%s\n" "not-saved"
      fi
      printf "%s\n" "mutter_devkit_restore_helper="
      if [[ -x /usr/local/libexec/fedora-shell/restore-mutter-devkit \
        && ! -L /usr/local/libexec/fedora-shell/restore-mutter-devkit ]] \
        && grep -Fq "fedora-shell-mutter-devkit-restore-v1" \
          /usr/local/libexec/fedora-shell/restore-mutter-devkit 2>/dev/null; then
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

guest_systemd_marker_evidence() {
  if ! fedora_container_exists; then
    printf '%s\n' 'guest_systemd_marker=container-not-installed'
    return 0
  fi
  # This is a read-only guest-root probe. It reports the exact marker and the
  # temporary backups used by start.sh or fedora-session; it never moves or
  # removes either path.
  # shellcheck disable=SC2016
  fedora_pd_login_root /bin/bash -c '
    marker=/run/systemd/seats
    backup=/run/systemd/seats.fedora-shell-backup
    session_backup=/tmp/fedora-runtime/systemd-seats-marker
    pid1=unknown
    [ -r /proc/1/comm ] && pid1="$(cat /proc/1/comm)"
    printf "guest_pid1=%s\n" "$pid1"
    [ -e "$marker" ] && printf "%s\n" "guest_systemd_marker=present" || printf "%s\n" "guest_systemd_marker=absent"
    [ -e "$backup" ] && printf "%s\n" "guest_systemd_marker_backup=present" || printf "%s\n" "guest_systemd_marker_backup=absent"
    [ -e "$session_backup" ] && printf "%s\n" "guest_session_marker_backup=present" || printf "%s\n" "guest_session_marker_backup=absent"
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
  printf 'android_apps_mode=%s\n' "$FEDORA_ANDROID_APPS_MODE"
  printf 'keyboard_mode=%s\n' "$FEDORA_KEYBOARD_MODE"
  printf '%s\n' 'keyboard_routing=focused-Termux:X11-Fedora-surface; Android global keys remain SystemUI-owned'
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
  printf 'system_bus_mode=%s\n' "$FEDORA_SYSTEM_BUS_MODE"
  printf 'devkit_debug=%s\n' "$FEDORA_DEVKIT_DEBUG"
  printf 'redacted=%s\n' "$([[ $REDACT -eq 1 ]] && echo yes || echo no)"
  printf 'state_dir=%s\n' "$FEDORA_STATE_DIR"
  printf 'install_root=%s\n' "$FEDORA_INSTALL_ROOT"
  printf 'container=%s\n' "$FEDORA_CONTAINER"
  printf 'container_installed=%s\n' "$(fedora_container_exists && echo yes || echo no)"
  printf 'container_running=%s\n' "$(fedora_container_running && echo yes || echo no)"
} > "$report"

capture 'free space' df -Pk "$FEDORA_USER_HOME"
capture 'Android RAM Plus / zRAM (read-only)' android_ramplus_snapshot
capture 'Android app bridge (read-only)' android_app_bridge_evidence
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
  capture 'Mutter Devkit viewer environment (filtered)' devkit_viewer_environment
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
  capture 'Fedora systemd marker (read-only)' guest_systemd_marker_evidence
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
  redacted_report="$(mktemp "${report%/*}/.fedora-redacted.XXXXXX" 2>/dev/null || true)"
  if [[ -n "$redacted_report" ]] \
    && fedora_report_path_is_safe "$redacted_report" \
    && sed -E \
    -e 's#(/data/data/[^[:space:]]+)#<termux-private-path>#g' \
    -e 's#(/home/[^[:space:]]+)#<home-path>#g' \
    -e 's#(\[?[^]]*(serial(no)?|imei|imsi|meid|ssid|bssid)[^]]*\]?[[:space:]]*[:=][[:space:]]*)[^[:space:]]+#\1<redacted>#Ig' \
    -e 's#((serial(no)?|imei|imsi|meid|ssid|bssid|android_id)[^:=]*[=:][[:space:]]*)[^[:space:]]+#\1<redacted>#Ig' \
    "$report" > "$redacted_report"; then
    chmod 600 "$redacted_report"
    mv -- "$redacted_report" "$report"
  else
    [[ -z "$redacted_report" ]] || rm -f -- "$redacted_report"
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
