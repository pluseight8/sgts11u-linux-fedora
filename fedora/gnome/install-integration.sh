#!/usr/bin/env bash
set -Eeuo pipefail

# Marker: fedora-shell-guest-integration-v1
[[ "$(id -u)" == 0 ]] || { printf '%s\n' 'Guest integration setup requires root.' >&2; exit 1; }
project_root="${FEDORA_GUEST_PROJECT_ROOT:-/opt/fedora-shell}"
bridge_source="$project_root/integration/android-bridge.sh"
app_config="$project_root/integration/android-apps.conf"
devkit_wrapper_source="$project_root/fedora/gnome/mutter-devkit-wrapper"
devkit_restore_source="$project_root/fedora/rootfs/restore-mutter-devkit.sh"
guest_bridge="/usr/local/bin/fedora-android-bridge"
devkit_wrapper_runtime="/usr/local/bin/fedora-mutter-devkit-wrapper"
devkit_real_dir="/usr/local/libexec/fedora-shell"
devkit_real="$devkit_real_dir/mutter-devkit.real"
devkit_real_owner="$devkit_real_dir/mutter-devkit.real.owner"
devkit_restore_runtime="$devkit_real_dir/restore-mutter-devkit"
devkit_target="/usr/libexec/mutter-devkit"
[[ -f "$bridge_source" && ! -L "$bridge_source" ]] || { printf 'Missing or symlinked bind-mounted bridge: %s\n' "$bridge_source" >&2; exit 1; }
[[ -f "$app_config" && ! -L "$app_config" ]] || { printf 'Missing or symlinked app allowlist: %s\n' "$app_config" >&2; exit 1; }
[[ -f "$devkit_wrapper_source" && ! -L "$devkit_wrapper_source" ]] || {
  printf 'Missing or symlinked Mutter Devkit wrapper: %s\n' "$devkit_wrapper_source" >&2
  exit 1
}
[[ -f "$devkit_restore_source" && ! -L "$devkit_restore_source" ]] || {
  printf 'Missing or symlinked Mutter Devkit restore helper: %s\n' "$devkit_restore_source" >&2
  exit 1
}

for directory in /usr/local/bin /usr/local/share/fedora-shell \
  /usr/local/libexec /usr/share/applications /usr/libexec; do
  if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
    printf 'Refusing to install integration through an unsafe directory: %s\n' "$directory" >&2
    exit 1
  fi
done
install -d -m 0755 /usr/local/bin /usr/local/share/fedora-shell \
  "$devkit_real_dir" /usr/share/applications
for directory in /usr/local/bin /usr/local/share/fedora-shell \
  "$devkit_real_dir" /usr/share/applications /usr/libexec; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    printf 'Integration directory became unavailable during setup: %s\n' "$directory" >&2
    exit 1
  }
done

atomic_install_file() {
  local source="$1"
  local destination="$2"
  local mode="${3:-0644}"
  local destination_dir temporary
  destination_dir="$(dirname -- "$destination")"
  [[ -d "$destination_dir" && ! -L "$destination_dir" ]] || return 1
  [[ ! -L "$destination" ]] || return 1
  temporary="$(mktemp "$destination_dir/.fedora-shell-install.XXXXXX")" || return 1
  if ! install -m "$mode" "$source" "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  [[ ! -L "$destination" ]] || {
    rm -f -- "$temporary"
    return 1
  }
  mv -f -- "$temporary" "$destination"
}

atomic_replace_from_stdin() {
  local destination="$1"
  local mode="$2"
  local destination_dir temporary
  destination_dir="$(dirname -- "$destination")"
  [[ -d "$destination_dir" && ! -L "$destination_dir" ]] || return 1
  [[ ! -L "$destination" ]] || return 1
  temporary="$(mktemp "$destination_dir/.fedora-shell-install.XXXXXX")" || return 1
  if ! cat > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod "$mode" "$temporary" || {
    rm -f -- "$temporary"
    return 1
  }
  [[ ! -L "$destination" ]] || {
    rm -f -- "$temporary"
    return 1
  }
  mv -f -- "$temporary" "$destination"
}

install_mutter_devkit_wrapper() {
  local package_owner=""

  # The wrapper is an intentional Fedora-only interposition at the compiled
  # Mutter libexec path. Never follow a symlink, and never take over a file
  # that is not owned by a Mutter RPM. Android files and settings are outside
  # this guest-root operation.
  if [[ -L "$devkit_target" ]]; then
    printf 'Preserving symlinked Mutter Devkit target: %s\n' "$devkit_target" >&2
    return 0
  fi
  if [[ -f "$devkit_target" ]] \
    && grep -Fq 'fedora-shell-mutter-devkit-wrapper-v1' "$devkit_target" 2>/dev/null; then
    if [[ ! -x "$devkit_real" || -L "$devkit_real" \
      || ! -f "$devkit_real_owner" || -L "$devkit_real_owner" ]] \
      || ! grep -Fq 'fedora-shell-mutter-devkit-real-v1' "$devkit_real_owner" 2>/dev/null; then
      printf 'Mutter Devkit wrapper has no trusted original binary: %s\n' "$devkit_real" >&2
      return 1
    fi
  else
    [[ -e "$devkit_target" ]] || {
      printf 'Mutter Devkit binary is not installed; wrapper was not enabled.\n' >&2
      return 0
    }
    [[ -x "$devkit_target" && -f "$devkit_target" ]] || {
      printf 'Mutter Devkit target is not an executable regular file; wrapper was not enabled: %s\n' \
        "$devkit_target" >&2
      return 0
    }
    if ! command -v rpm >/dev/null 2>&1; then
      printf 'RPM ownership cannot be verified; preserving %s and leaving the shim disabled.\n' \
        "$devkit_target" >&2
      return 0
    fi
    package_owner="$(rpm -qf "$devkit_target" 2>/dev/null || true)"
    [[ "$package_owner" == mutter-* ]] || {
      printf 'Preserving non-Mutter executable at %s (RPM owner: %s).\n' \
        "$devkit_target" "${package_owner:-unknown}" >&2
      return 0
    }
    if [[ -e "$devkit_real" || -e "$devkit_real_owner" ]]; then
      if [[ ! -f "$devkit_real" || -L "$devkit_real" \
        || ! -f "$devkit_real_owner" || -L "$devkit_real_owner" ]] \
        || ! grep -Fq 'fedora-shell-mutter-devkit-real-v1' "$devkit_real_owner"; then
        printf 'Refusing to overwrite an unowned saved Mutter Devkit binary: %s\n' "$devkit_real" >&2
        return 1
      fi
    fi
    atomic_install_file "$devkit_target" "$devkit_real" 0755 || {
      printf 'Could not save the original Mutter Devkit binary: %s\n' "$devkit_real" >&2
      return 1
    }
    atomic_replace_from_stdin "$devkit_real_owner" 0644 <<'EOF'
# Marker: fedora-shell-mutter-devkit-real-v1
source=/usr/libexec/mutter-devkit
owner=fedora-shell
EOF
  fi

  if [[ -e "$devkit_wrapper_runtime" ]] \
    && ! grep -Fq 'fedora-shell-mutter-devkit-wrapper-v1' "$devkit_wrapper_runtime" 2>/dev/null; then
    printf 'Refusing to overwrite non-project wrapper path: %s\n' "$devkit_wrapper_runtime" >&2
    return 1
  fi
  atomic_install_file "$devkit_wrapper_source" "$devkit_wrapper_runtime" 0755 || {
    printf 'Could not install the Fedora Mutter Devkit wrapper runtime.\n' >&2
    return 1
  }
  atomic_install_file "$devkit_wrapper_source" "$devkit_target" 0755 || {
    printf 'Could not install the Fedora Mutter Devkit wrapper at %s.\n' "$devkit_target" >&2
    return 1
  }
  printf 'Fedora Mutter Devkit activation shim enabled; original saved at %s.\n' "$devkit_real" >&2
}

if [[ -L "$devkit_restore_runtime" ]] \
  || { [[ -e "$devkit_restore_runtime" ]] \
    && ! grep -Fq 'fedora-shell-mutter-devkit-restore-v1' "$devkit_restore_runtime" 2>/dev/null; }; then
  printf 'Refusing to overwrite non-project Mutter Devkit restore helper: %s\n' \
    "$devkit_restore_runtime" >&2
  exit 1
fi
atomic_install_file "$devkit_restore_source" "$devkit_restore_runtime" 0755 || {
  printf 'Could not install the Fedora Mutter Devkit package helper.\n' >&2
  exit 1
}
install_mutter_devkit_wrapper
# The source bridge is a Termux-side script and intentionally has a Termux
# interpreter path. Fedora cannot execute that path inside PRoot, so install
# a Fedora-native wrapper that reaches the source through the project bind
# mount. Preserve unrelated administrator-owned files.
if [[ -L "$guest_bridge" ]]; then
  printf 'Preserving symlinked bridge: %s\n' "$guest_bridge" >&2
elif [[ -e "$guest_bridge" ]] \
  && ! grep -Eq 'fedora-shell-guest-android-bridge-v1|fedora-android-bridge-v2' \
    "$guest_bridge" 2>/dev/null; then
  printf 'Preserving non-project bridge: %s\n' "$guest_bridge" >&2
else
  atomic_replace_from_stdin "$guest_bridge" 0755 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
# Marker: fedora-shell-guest-android-bridge-v1
bridge_root="${FEDORA_GUEST_PROJECT_ROOT:-/opt/fedora-shell}"
bridge="$bridge_root/integration/android-bridge.sh"
if [[ ! -f "$bridge" || -L "$bridge" ]]; then
  printf '[fedora-android-bridge] project bridge is unavailable: %s\n' "$bridge" >&2
  exit 1
fi
exec /bin/bash "$bridge" "$@"
EOF
fi
atomic_install_file "$app_config" /usr/local/share/fedora-shell/android-apps.conf

refresh_desktop=/usr/share/applications/fedora-android-refresh.desktop
if [[ -L "$refresh_desktop" ]]; then
  printf 'Preserving symlinked desktop entry: %s\n' "$refresh_desktop" >&2
elif [[ -e "$refresh_desktop" ]] \
  && ! grep -Fq 'X-Fedora-Shell-Android-Refresh=true' "$refresh_desktop" 2>/dev/null; then
  printf 'Preserving non-project desktop entry: %s\n' "$refresh_desktop" >&2
else
  atomic_replace_from_stdin "$refresh_desktop" 0644 <<'EOF'
[Desktop Entry]
Type=Application
Name=Refresh Android applications
Comment=Refresh user-installed Android application entries in Fedora
Exec=/usr/local/bin/fedora-android-bridge sync-apps
Icon=view-refresh
Terminal=false
Categories=Utility;
OnlyShowIn=GNOME;
X-Fedora-Shell-Android=true
X-Fedora-Shell-Android-Refresh=true
EOF
fi

declare -A current_static=()
while IFS='|' read -r app_id label target icon_name; do
  [[ -z "$app_id" || "${app_id:0:1}" == '#' ]] && continue
  [[ "$app_id" =~ ^[a-z0-9-]+$ ]] || { printf 'Skipping invalid app id: %s\n' "$app_id" >&2; continue; }
  if [[ "$label" == *$'\n'* || "$label" == *$'\r'* ]]; then
    printf 'Skipping label with a newline for %s\n' "$app_id" >&2
    continue
  fi
  [[ -n "$label" ]] || label="$app_id"
  [[ "$icon_name" =~ ^[a-zA-Z0-9._+-]+$ ]] || icon_name=application-x-executable
  case "$target" in
    intent:)
      printf 'Skipping empty intent for %s\n' "$app_id" >&2
      continue
      ;;
    intent:*)
      action="${target#intent:}"
      [[ "$action" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$ ]] || {
        printf 'Skipping invalid intent for %s\n' "$app_id" >&2
        continue
      }
      ;;
    package:*)
      package_name="${target#package:}"
      [[ "$package_name" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]] || {
        printf 'Skipping invalid package target for %s\n' "$app_id" >&2
        continue
      }
      ;;
    *)
      printf 'Skipping unsupported target for %s\n' "$app_id" >&2
      continue
      ;;
  esac
  desktop="/usr/share/applications/fedora-android-${app_id}.desktop"
  if [[ -L "$desktop" ]]; then
    printf 'Preserving symlinked desktop entry: %s\n' "$desktop" >&2
    continue
  fi
  if [[ -e "$desktop" ]] \
    && ! grep -Fq 'X-Fedora-Shell-Android=true' "$desktop" 2>/dev/null; then
    printf 'Preserving non-project desktop entry: %s\n' "$desktop" >&2
    continue
  fi
  desktop_tmp="$(mktemp "$(dirname -- "$desktop")/.fedora-shell-desktop.XXXXXX")"
  if ! {
    printf '%s\n' '[Desktop Entry]'
    printf '%s\n' 'Type=Application'
    printf 'Name=%s\n' "$label"
    printf '%s\n' 'Comment=Open an Android activity through Fedora Android Bridge'
    printf 'Exec=/usr/local/bin/fedora-android-bridge launch-app %s\n' "$app_id"
    printf 'Icon=%s\n' "$icon_name"
    printf '%s\n' 'Terminal=false'
    printf '%s\n' 'Categories=Utility;'
    printf '%s\n' 'X-Fedora-Shell-Android=true'
    printf 'X-Fedora-Shell-Target=%s\n' "$target"
  } > "$desktop_tmp"; then
    rm -f -- "$desktop_tmp"
    exit 1
  fi
  chmod 0644 "$desktop_tmp"
  [[ ! -L "$desktop" ]] || {
    rm -f -- "$desktop_tmp"
    printf 'Desktop entry became a symlink during setup: %s\n' "$desktop" >&2
    exit 1
  }
  mv -f -- "$desktop_tmp" "$desktop"
  current_static["$app_id"]=1
done < "$app_config"

# Reconcile only project-owned static entries. Dynamic user entries live under
# each user's data directory and are intentionally handled by sync-apps.
for desktop in /usr/share/applications/fedora-android-*.desktop; do
  [[ -f "$desktop" && ! -L "$desktop" ]] || continue
  grep -Fq 'X-Fedora-Shell-Android=true' "$desktop" 2>/dev/null || continue
  grep -Fq 'X-Fedora-Shell-Android-Refresh=true' "$desktop" 2>/dev/null && continue
  app_id="${desktop##*/fedora-android-}"
  app_id="${app_id%.desktop}"
  [[ -n "${current_static[$app_id]:-}" ]] || rm -f -- "$desktop"
done

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
