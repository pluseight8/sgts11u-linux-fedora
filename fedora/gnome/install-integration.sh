#!/usr/bin/env bash
set -Eeuo pipefail

# Marker: fedora-shell-guest-integration-v1
[[ "$(id -u)" == 0 ]] || { printf '%s\n' 'Guest integration setup requires root.' >&2; exit 1; }
project_root="${FEDORA_GUEST_PROJECT_ROOT:-/opt/fedora-shell}"
bridge_source="$project_root/integration/android-bridge.sh"
app_config="$project_root/integration/android-apps.conf"
[[ -f "$bridge_source" ]] || { printf 'Missing bind-mounted bridge: %s\n' "$bridge_source" >&2; exit 1; }
[[ -f "$app_config" ]] || { printf 'Missing app allowlist: %s\n' "$app_config" >&2; exit 1; }

install -d -m 0755 /usr/local/bin /usr/local/share/fedora-shell /usr/share/applications
install -m 0755 "$bridge_source" /usr/local/bin/fedora-android-bridge
install -m 0644 "$app_config" /usr/local/share/fedora-shell/android-apps.conf

while IFS='|' read -r app_id label package_name icon_name; do
  [[ -z "$app_id" || "${app_id:0:1}" == '#' ]] && continue
  [[ "$app_id" =~ ^[a-z0-9-]+$ ]] || { printf 'Skipping invalid app id: %s\n' "$app_id" >&2; continue; }
  [[ "$package_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]] || { printf 'Skipping invalid package for %s\n' "$app_id" >&2; continue; }
  desktop="/usr/share/applications/fedora-android-${app_id}.desktop"
  cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$label
Comment=Open the Android app through Fedora Android Bridge
Exec=/usr/local/bin/fedora-android-bridge launch-app $app_id
Icon=$icon_name
Terminal=false
Categories=Utility;
X-Fedora-Shell-Android=true
X-Fedora-Shell-Package=$package_name
EOF
  chmod 0644 "$desktop"
done < "$app_config"
