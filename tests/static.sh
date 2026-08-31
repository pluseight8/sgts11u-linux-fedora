#!/usr/bin/env bash
set -Eeuo pipefail

# Static checks run on a normal Linux CI host; Termux scripts are parsed with
# bash and are not executed here because Android/system commands are absent.
root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

while IFS= read -r -d '' file; do
  if ! bash -n "$file"; then
    printf 'syntax error: %s\n' "$file" >&2
    status=1
  fi
done < <(find "$root/scripts" "$root/gpu" "$root/audio" "$root/input" "$root/integration" "$root/fedora" -type f -name '*.sh' -print0)

if ! bash -n "$root/fedora/gnome/fedora-run"; then
  printf '%s\n' 'syntax error: fedora/gnome/fedora-run' >&2
  status=1
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x \
    "$root/scripts"/*.sh \
    "$root/scripts/lib"/*.sh \
    "$root/gpu/scripts"/*.sh \
    "$root/audio"/*.sh \
    "$root/input"/*.sh \
    "$root/integration"/*.sh \
    "$root/integration/boot"/* \
    "$root/integration/widget"/* \
    "$root/fedora/rootfs"/*.sh \
    "$root/fedora/gnome"/*.sh || status=1
fi

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$root/android/app/src/main/AndroidManifest.xml" || status=1
fi

if ! grep -Fxq 'mutter-devkit' "$root/fedora/packages/gnome-packages.txt"; then
  printf '%s\n' 'mutter-devkit must remain in the Fedora GNOME package manifest' >&2
  status=1
fi
for executable in \
  scripts/install.sh \
  scripts/bootstrap.sh \
  scripts/remove.sh \
  scripts/start.sh \
  scripts/stop.sh \
  scripts/update.sh \
  scripts/uninstall.sh \
  fedora/gnome/fedora-session \
  fedora/gnome/fedora-run \
  fedora/rootfs/install-gnome.sh; do
  if [[ ! -x "$root/$executable" ]]; then
    printf 'required executable bit is missing: %s\n' "$executable" >&2
    status=1
  fi
done
if grep -Fxq 'xorg-x11-server-utils' "$root/fedora/packages/gnome-packages.txt"; then
  printf '%s\n' 'unavailable xorg-x11-server-utils must not be a required package' >&2
  status=1
fi
if ! grep -Fq -- '--devkit' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'GNOME 49+ Devkit launch path is missing' >&2
  status=1
fi
if ! grep -Fq 'FEDORA_PORTAL_MODE' "$root/scripts/install.sh" \
  || ! grep -Fq 'FEDORA_PORTAL_MODE' "$root/scripts/start.sh" \
  || ! grep -Fq 'portal_fuse_available' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'portal mode and FUSE-aware startup guard are missing' >&2
  status=1
fi
if ! grep -Fq 'LIBGL_ALWAYS_SOFTWARE=1' "$root/scripts/start.sh"; then
  printf '%s\n' 'safe software GPU fallback is missing' >&2
  status=1
fi
if ! grep -Fq 'TERMUX_X11_LEGACY_DRAWING' "$root/scripts/start.sh" \
  || ! grep -Fq 'has no socket' "$root/scripts/start.sh" \
  || ! grep -Fq 'different drawing flags' "$root/scripts/start.sh" \
  || ! grep -Fq 'termux-x11.args' "$root/scripts/stop.sh"; then
  printf '%s\n' 'Termux:X11 black-screen/stale-socket recovery is missing' >&2
  status=1
fi
if ! grep -Fq 'FEDORA_TERMUX_X11_AUTO_OPEN' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'Android API' "$root/scripts/start.sh" \
  || ! grep -Fq 'open the APK manually' "$root/scripts/start.sh"; then
  printf '%s\n' 'Android background-activity-safe Termux:X11 startup is missing' >&2
  status=1
fi
if ! grep -Fq 'fedora_sync_project_tree' "$root/scripts/install.sh" \
  || ! grep -Fq 'FEDORA_CHECKOUT_ROOT' "$root/scripts/update.sh"; then
  printf '%s\n' 'project checkout synchronization is missing' >&2
  status=1
fi
if ! grep -Fq 'virglrenderer-android' "$root/scripts/install.sh" \
  || ! grep -Fq 'auto mode keeps the stable software renderer' "$root/scripts/start.sh"; then
  printf '%s\n' 'experimental GPU must remain explicit and opt-in' >&2
  status=1
fi
if ! grep -Fq 'Refusing to remove unowned file' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'return 1' "$root/scripts/lib/common.sh"; then
  printf '%s\n' 'owned-file removal guard is missing' >&2
  status=1
fi
if ! grep -Fq -- '--redact' "$root/scripts/diagnostics.sh"; then
  printf '%s\n' 'diagnostic redaction option is missing' >&2
  status=1
fi
if ! grep -Fq 'fedora_resolve_memory_profile' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'FEDORA_MEMORY_PROFILE' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'MALLOC_ARENA_MAX' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'MALLOC_TRIM_THRESHOLD_' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq '2560x1600' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'low-memory profile support is missing' >&2
  status=1
fi
if ! grep -Fq 'fedora_termux_full_upgrade' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'force-confold' "$root/scripts/bootstrap.sh"; then
  printf '%s\n' 'non-interactive complete Termux upgrade helper is missing' >&2
  status=1
fi
if ! grep -Fq 'fedora_repair_project_modes' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'fedora_repair_project_modes "$source_project_root"' "$root/scripts/install.sh" \
  || ! grep -Fq 'fedora_repair_project_modes "$checkout_root"' "$root/scripts/update.sh" \
  || ! grep -Fq 'fedora_repair_project_modes "$TARGET_DIR"' "$root/scripts/bootstrap.sh"; then
  printf '%s\n' 'project executable-mode repair is missing' >&2
  status=1
fi
if ! grep -Fq 'enable-animations=false' "$root/fedora/config/dconf.ini"; then
  printf '%s\n' 'low-overhead GNOME defaults are missing' >&2
  status=1
fi
if ! grep -Fq 'fedora_config_override_names' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'printf -v' "$root/scripts/lib/common.sh"; then
  printf '%s\n' 'environment overrides must take precedence over config.env' >&2
  status=1
fi
if ! grep -Fq 'report_process_exit' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'GNOME Shell Devkit crashed' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'GNOME crash evidence/reporting guard is missing' >&2
  status=1
fi
if ! grep -Fq 'Starting minimal PipeWire display transport' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'wait_for_devkit_viewer' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'process_ids_by_name' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'FEDORA_DEVKIT_GDK_BACKEND' "$root/scripts/start.sh" \
  || ! grep -Fq 'pw-cli' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'PIPEWIRE_RUNTIME_DIR' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'PIPEWIRE_RUNTIME_DIR=/tmp/fedora-runtime' "$root/scripts/start.sh" \
  || ! grep -Fq 'pipewire-0.lock' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'PipeWire native display transport is unavailable' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'Mutter Devkit PipeWire/viewer health guards are missing' >&2
  status=1
fi
if ! grep -Fq 'DBUS_SYSTEM_BUS_ADDRESS' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'GIO_USE_VFS' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq '<servicedir>' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'dbus-services' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'org.freedesktop.portal' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'PRoot D-Bus/GVFS compatibility guards are missing' >&2
  status=1
fi
if grep -Fq 'send_destination_prefix' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'portal D-Bus policy must not broadly deny GNOME/Mutter requests' >&2
  status=1
fi
if grep -Fq 'source "$session_state_host"' "$root/scripts/start.sh"; then
  printf '%s\n' 'start.sh must not reuse stale Wayland session metadata' >&2
  status=1
fi

grep -R -n --exclude-dir=.git --exclude='*.md' \
  -E '(^|[[:space:]])(setenforce[[:space:]]+0|magisk|heimdall|(^|[[:space:]])odin([[:space:]]|$))' \
  "$root/scripts" "$root/gpu" "$root/audio" "$root/input" "$root/integration" "$root/fedora" \
  && { printf '%s\n' 'forbidden root/flash command found' >&2; status=1; } || true

if (( status == 0 )); then
  printf '%s\n' 'static checks passed'
fi
exit "$status"
