#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-audio-stop-v1
AUDIO_SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$AUDIO_SCRIPT_DIR/../scripts/lib/common.sh"

fedora_init_state
fedora_kill_owned_pid "$FEDORA_PID_DIR/pulseaudio.pid" pulseaudio
