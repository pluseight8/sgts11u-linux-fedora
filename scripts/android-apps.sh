#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-android-apps-v1
#
# Refresh the Fedora-side catalog of Android applications without starting a
# hidden Linux session. The actual Android package query and explicit launch
# remain in integration/android-bridge-broker.sh, which runs in the ordinary
# Termux UID. This helper only asks an already-running Fedora session to write
# user-owned .desktop entries.

FEDORA_ENTRY_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$FEDORA_ENTRY_DIR/lib/common.sh"

fedora_init_log
fedora_require_termux
fedora_require_non_root
fedora_require_container

runtime="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime/android-bridge"
if ! fedora_container_running; then
  fedora_die "Fedora Linux Mode is not running; refresh Android app entries after starting it."
  exit 1
fi
if [[ ! -d "$runtime" || -L "$runtime" \
  || ! -d "$runtime/requests" || -L "$runtime/requests" \
  || ! -d "$runtime/responses" || -L "$runtime/responses" ]]; then
  fedora_die "Android app broker is not running; keep Termux:X11 visible and retry."
  exit 1
fi

fedora_log "Refreshing Fedora Android application entries (read-only Android hand-off)."
exec fedora_pd_login /usr/bin/env \
  "FEDORA_ANDROID_APPS_SCOPE=$FEDORA_ANDROID_APPS_SCOPE" \
  /usr/local/bin/fedora-android-bridge sync-apps
