#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-diagnostics-v1
FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"

MODE=quick
INCLUDE_FEDORA=1
FRAME_PACING=0

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/diagnostics.sh [OPTIONS]

Options:
  --quick             collect a small local report (default)
  --full              include Android display/input/audio and Termux inventory
  --fedora            include Fedora guest probes
  --no-fedora         skip guest probes
  --frame-pacing      append the frame-pacing proxy report
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

{
  printf 'fedora-shell-diagnostics-v1\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'mode=%s\n' "$MODE"
  printf 'termux_version=%s\n' "${TERMUX_VERSION:-unknown}"
  printf 'uname=%s\n' "$(uname -a 2>/dev/null || true)"
  printf 'uname_m=%s\n' "$(uname -m 2>/dev/null || true)"
  printf 'model=%s\n' "$(fedora_getprop ro.product.model)"
  printf 'android_release=%s\n' "$(fedora_getprop ro.build.version.release)"
  printf 'android_api=%s\n' "$(fedora_getprop ro.build.version.sdk)"
  printf 'board=%s\n' "$(fedora_getprop ro.board.platform)"
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
  if [[ -x /system/bin/dumpsys ]]; then
    capture 'Android display' /system/bin/dumpsys display || true
    capture 'SurfaceFlinger' /system/bin/dumpsys SurfaceFlinger || true
    capture 'Android input' /system/bin/dumpsys input || true
    capture 'Android audio' /system/bin/dumpsys audio || true
  fi
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

chmod 600 "$report"
printf 'report=%s\n' "$report"
printf '%s\n' 'Redact serial/IMEI/SSID/private paths before sharing a full report.'
