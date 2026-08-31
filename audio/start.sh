#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-audio-start-v1
AUDIO_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$AUDIO_SCRIPT_DIR/../scripts/lib/common.sh"

fedora_require_termux
fedora_require_non_root
fedora_init_state

case "$FEDORA_AUDIO_MODE" in
  none|disabled) exit 0 ;;
  auto|termux|pulseaudio) ;;
  *) fedora_die "Unknown FEDORA_AUDIO_MODE=$FEDORA_AUDIO_MODE"; exit 64 ;;
esac

if ! fedora_have_cmd pulseaudio; then
  fedora_warn "Termux pulseaudio is not installed; audio remains Android-bridged and GNOME audio is untested."
  exit 0
fi

if pulseaudio --check >/dev/null 2>&1; then
  fedora_log "Reusing the existing Termux PulseAudio daemon."
  exit 0
fi

fedora_log "Starting optional Termux PulseAudio daemon."
pulseaudio --daemonize=no --exit-idle-time=-1 \
  >> "$FEDORA_LOG_DIR/pulseaudio.log" 2>&1 &
pulse_pid=$!
printf '%s\n' "$pulse_pid" > "$FEDORA_PID_DIR/pulseaudio.pid"
chmod 600 "$FEDORA_PID_DIR/pulseaudio.pid"
sleep 0.3
