#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-input-probe-v1
INPUT_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$INPUT_SCRIPT_DIR/../scripts/lib/common.sh"

fedora_require_termux
fedora_require_non_root
fedora_init_state
report="${1:-$FEDORA_LOG_DIR/input-probe-$(date -u +%Y%m%dT%H%M%SZ).txt}"
umask 077

{
  printf 'fedora-shell-input-probe-v1\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'model=%s\n' "$(fedora_getprop ro.product.model)"
  printf '\n[Termux:X11 preferences]\n'
  if fedora_have_cmd termux-x11-preference; then termux-x11-preference list || true; else printf 'absent\n'; fi
  printf '\n[Android input device inventory]\n'
  if [[ -x /system/bin/dumpsys ]]; then /system/bin/dumpsys input 2>&1 | sed -n '1,320p' || true; else printf 'dumpsys unavailable\n'; fi
  printf '\n[Linux-visible event inventory]\n'
  if fedora_have_cmd getevent; then getevent -lp 2>&1 | sed -n '1,220p' || true; else printf 'getevent unavailable\n'; fi
  printf '\n[Wayland protocol note]\n'
  printf '%s\n' 'This probe intentionally does not stream raw stylus/touch events. Record gestures manually after the session is running.'
} > "$report" 2>&1
chmod 600 "$report"
printf 'report=%s\n' "$report"
