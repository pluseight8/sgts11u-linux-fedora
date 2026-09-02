#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-gpu-probe-v1
GPU_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$GPU_SCRIPT_DIR/../../scripts/lib/common.sh"

fedora_require_termux
fedora_require_non_root
fedora_init_state

report="${1:-$FEDORA_LOG_DIR/gpu-probe-$(date -u +%Y%m%dT%H%M%SZ)-$$.txt}"
report_parent="${report%/*}"
[[ -n "$report_parent" ]] || report_parent=/
fedora_prepare_directories "$report_parent" || {
  fedora_die "Could not prepare the GPU report directory: $report_parent"
  exit 1
}
fedora_report_path_is_safe "$report" || {
  fedora_die "Refusing an unsafe GPU report path: $report"
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

{
  printf 'fedora-shell-gpu-probe-v1\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'uname_m=%s\n' "$(uname -m)"
  printf 'termux_version=%s\n' "${TERMUX_VERSION:-unknown}"
} > "$report"

for property in \
  ro.product.model \
  ro.build.version.release \
  ro.build.version.sdk \
  ro.board.platform \
  ro.hardware.egl \
  ro.hardware.vulkan \
  ro.hardware.gpu \
  debug.hwui.renderer; do
  {
    printf '%s=' "$property"
    fedora_getprop "$property"
  } >> "$report"
done

for command_name in \
  virgl_test_server_android \
  eglinfo \
  glxinfo \
  vulkaninfo \
  termux-x11 \
  termux-x11-preference; do
  if fedora_have_cmd "$command_name"; then
    printf 'command_%s=%s\n' "$command_name" "$(command -v "$command_name")" >> "$report"
  else
    printf 'command_%s=absent\n' "$command_name" >> "$report"
  fi
done

if [[ -x /system/bin/dumpsys ]]; then
  capture 'SurfaceFlinger display summary' /system/bin/dumpsys SurfaceFlinger --display-id
  capture 'SurfaceFlinger layers' /system/bin/dumpsys SurfaceFlinger --list
fi
if fedora_have_cmd termux-x11-preference; then
  capture 'Termux:X11 preferences' termux-x11-preference list
fi

printf 'report=%s\n' "$report"
