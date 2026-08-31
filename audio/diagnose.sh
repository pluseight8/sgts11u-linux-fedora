#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-audio-diagnose-v1
AUDIO_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$AUDIO_SCRIPT_DIR/../scripts/lib/common.sh"

fedora_require_termux
fedora_require_non_root
fedora_init_state
report="${1:-$FEDORA_LOG_DIR/audio-$(date -u +%Y%m%dT%H%M%SZ).txt}"
umask 077

{
  printf 'fedora-shell-audio-diagnose-v1\n'
  printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'audio_mode=%s\n' "$FEDORA_AUDIO_MODE"
  for command_name in termux-volume termux-microphone-record termux-audio-info pulseaudio; do
    if fedora_have_cmd "$command_name"; then
      printf 'command_%s=%s\n' "$command_name" "$(command -v "$command_name")"
    else
      printf 'command_%s=absent\n' "$command_name"
    fi
  done
  printf '\n[termux-volume]\n'
  if fedora_have_cmd termux-volume; then termux-volume || true; else printf 'absent\n'; fi
  printf '\n[termux-audio-info]\n'
  if fedora_have_cmd termux-audio-info; then termux-audio-info || true; else printf 'absent\n'; fi
  printf '\n[termux-microphone-record help]\n'
  if fedora_have_cmd termux-microphone-record; then termux-microphone-record --help || true; else printf 'absent\n'; fi
  printf '\n[pulseaudio]\n'
  if fedora_have_cmd pulseaudio; then
    if pulseaudio --check; then printf 'check_exit=0\n'; else printf 'check_exit=%s\n' "$?"; fi
  else
    printf 'absent\n'
  fi
} > "$report" 2>&1 || true
chmod 600 "$report"
printf 'report=%s\n' "$report"
