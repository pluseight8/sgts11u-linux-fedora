#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-frame-pacing-v1
GPU_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$GPU_SCRIPT_DIR/../../scripts/lib/common.sh"

DURATION=10
while (( $# > 0 )); do
  case "$1" in
    --seconds)
      (( $# >= 2 )) || { printf '%s\n' '--seconds needs a value' >&2; exit 64; }
      DURATION="$2"
      shift 2
      ;;
    -h|--help)
      printf '%s\n' 'Usage: measure-frame-pacing.sh [--seconds N]'
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done
[[ "$DURATION" =~ ^[0-9]+$ ]] || { printf '%s\n' '--seconds must be an integer' >&2; exit 64; }

fedora_require_termux
fedora_require_non_root
fedora_require_container
fedora_init_state
report="$FEDORA_LOG_DIR/frame-pacing-$(date -u +%Y%m%dT%H%M%SZ).txt"
umask 077

{
  printf 'fedora-shell-frame-pacing-v1\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'duration_seconds=%s\n' "$DURATION"
  printf '\n[Android refresh settings]\n'
  if [[ -x /system/bin/settings ]]; then
    /system/bin/settings get system peak_refresh_rate || true
    /system/bin/settings get system min_refresh_rate || true
    /system/bin/settings get system user_refresh_rate || true
  else
    printf 'settings command unavailable\n'
  fi
  printf '\n[Android display summary]\n'
  if [[ -x /system/bin/dumpsys ]]; then
    /system/bin/dumpsys display 2>&1 | sed -n '1,260p' || true
  else
    printf 'dumpsys unavailable\n'
  fi
  printf '\n[Session metadata]\n'
  session_state="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/fedora-session-state.env"
  if [[ -r "$session_state" ]]; then
    sed -n '1,40p' "$session_state"
  else
    printf 'No active Fedora Wayland session metadata found.\n'
  fi
} > "$report" 2>&1

if fedora_container_running && [[ -r "$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/fedora-session-state.env" ]]; then
  # shellcheck disable=SC1090,SC1091
  source "$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/fedora-session-state.env" || true
  {
    printf '\n[Fedora Wayland client proxy]\n'
    fedora_pd_login /usr/bin/env \
      "DISPLAY=${DISPLAY:-$FEDORA_DISPLAY}" \
      "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}" \
      "XDG_RUNTIME_DIR=/tmp/fedora-runtime" \
      "FEDORA_FRAME_SECONDS=$DURATION" \
      /usr/local/bin/fedora-frame-pacing
  } >> "$report" 2>&1 || true
else
  printf '\n[Fedora Wayland client proxy]\nFedora session is not active; skipped.\n' >> "$report"
fi

chmod 600 "$report"
printf 'report=%s\n' "$report"
printf '%s\n' 'Interpretation: a refresh-rate setting or mode line is not proof of 120 Hz presentation. Inspect client output and dropped-frame evidence on the actual tablet.'
