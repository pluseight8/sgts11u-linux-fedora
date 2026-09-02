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
if ! bash -n "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'syntax error: fedora/gnome/fedora-session' >&2
  status=1
fi
if ! bash -n "$root/fedora/gnome/mutter-devkit-wrapper"; then
  printf '%s\n' 'syntax error: fedora/gnome/mutter-devkit-wrapper' >&2
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
  scripts/android-apps.sh \
  scripts/update.sh \
  scripts/uninstall.sh \
  scripts/linux-mode.sh \
  input/keyboard-mode.sh \
  integration/android-bridge.sh \
  integration/android-bridge-broker.sh \
  integration/android-memory-governor.sh \
  fedora/gnome/fedora-session \
  fedora/gnome/fedora-run \
  fedora/gnome/mutter-devkit-wrapper \
  fedora/rootfs/restore-mutter-devkit.sh \
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
  || ! grep -Fq '1920x1200' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'FEDORA_NESTED_XWAYLAND' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'calendar_services_disabled' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'MALLOC_ARENA_MAX' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'low-memory profile support is missing' >&2
  status=1
fi
if ! grep -Fq 'FEDORA_NESTED_MODE_SPECS=1600x1000' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'MALLOC_ARENA_MAX=1' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'MALLOC_TRIM_THRESHOLD_=65536' "$root/scripts/linux-mode.sh"; then
  printf '%s\n' 'maximum Fedora-only memory profile contract is missing' >&2
  status=1
fi
if ! grep -Fq 'FEDORA_ANDROID_APPS_MODE' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'FEDORA_ANDROID_APPS_SCOPE' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'FEDORA_ANDROID_APPS_MODE' "$root/scripts/install.sh" \
  || ! grep -Fq 'FEDORA_ANDROID_APPS_SCOPE' "$root/scripts/install.sh" \
  || ! grep -Fq 'ensure_android_bridge_broker' "$root/scripts/start.sh" \
  || ! grep -Fq 'android-bridge-broker.sh' "$root/scripts/stop.sh" \
  || ! grep -Fq 'sync_android_app_desktops' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'Android app broker lifecycle integration is missing' >&2
  status=1
fi
if ! grep -Fq 'fedora_atomic_write' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'fedora_atomic_write "$x11_pid_file"' "$root/scripts/start.sh" \
  || ! grep -Fq 'fedora_atomic_write "$FEDORA_STATE_DIR/session-host.env"' "$root/scripts/start.sh" \
  || ! grep -Fq 'fedora_atomic_write "$FEDORA_STATE_DIR/install-device-probe.env"' "$root/scripts/install.sh" \
  || ! grep -Fq 'fedora_atomic_write "$MODE_LOCK_DIR/owner"' "$root/scripts/linux-mode.sh"; then
  printf '%s\n' 'Termux state and PID files must use the shared atomic writer' >&2
  status=1
fi
if ! grep -Fq 'fedora-android-bridge-broker-v1' "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq 'list-apps' "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq 'launch-package' "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq 'query-activities' "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq 'package_output_is_valid' "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq 'FEDORA_ANDROID_BRIDGE_DIR' "$root/scripts/start.sh"; then
  printf '%s\n' 'read-only Android app broker protocol is missing' >&2
  status=1
fi
if ! grep -Fq 'X-Fedora-Shell-Android-Dynamic=true' "$root/integration/android-bridge.sh" \
  || ! grep -Fq 'fedora-android-user-' "$root/integration/android-bridge.sh" \
  || ! grep -Fq 'package_output_is_valid' "$root/integration/android-bridge.sh" \
  || ! grep -Fq 'fedora-android-refresh.desktop' "$root/fedora/gnome/install-integration.sh" \
  || ! grep -Fq 'Android applications are displayed by Android' "$root/integration/android-bridge.sh"; then
  printf '%s\n' 'Fedora Android application desktop integration is missing' >&2
  status=1
fi
if ! grep -Fq 'FEDORA_ANDROID_APPS_SCOPE="${FEDORA_ANDROID_APPS_SCOPE:-all}"' \
    "$root/integration/android-bridge.sh" \
  || ! grep -Fq 'scope="${1:-user}"' "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq 'launchable system/user packages' "$root/AUDIT.md"; then
  printf '%s\n' 'all-scope Android launcher enumeration is missing' >&2
  status=1
fi
if ! grep -Fq 'fedora-shell-android-apps-v1' "$root/scripts/android-apps.sh" \
  || ! grep -Fq 'sync-apps' "$root/scripts/android-apps.sh" \
  || ! grep -Fq 'android-apps.sh' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/BridgeClient.java" \
  || ! grep -Fq 'Refresh Android apps in Fedora' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'handleAndroidLaunchIntent' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'fedora-shell://android/launch?package=' "$root/integration/android-bridge.sh" \
  || ! grep -Fq 'fedora-shell://android/launch?package=' "$root/integration/android-bridge-broker.sh"; then
  printf '%s\n' 'Android app catalog refresh GUI path is missing' >&2
  status=1
fi
if ! grep -Fq 'Android deep sleep — only manual guidance' \
  "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'showAndroidDeepSleepGuidance' \
    "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'manual-only' "$root/android/README.md" \
  || ! grep -Fq 'Глубокий сон Android (только инструкция)' \
    "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'ACTION_OPEN_CHECKABLE_LISTACTIVITY' \
    "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'com.samsung.android.lool' "$root/android/app/src/main/AndroidManifest.xml"; then
  printf '%s\n' 'Android deep-sleep guidance must remain manual and non-mutating' >&2
  status=1
fi
if ! grep -Fq 'FEDORA_KEYBOARD_MODE' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'FEDORA_KEYBOARD_MODE' "$root/scripts/install.sh" \
  || ! grep -Fq 'FEDORA_KEYBOARD_MODE=$FEDORA_KEYBOARD_MODE' "$root/scripts/start.sh" \
  || ! grep -Fq 'FEDORA_KEYBOARD_MODE' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'configure_keyboard_mode' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'XKB_CONFIG_ROOT=/usr/share/X11/xkb' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'unset XKB_CONFIG_ROOT' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'Linux Mode keyboard focus' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'showKeyboardGuidance' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'termux-x11-preference list' "$root/input/keyboard-mode.sh" \
  || ! grep -Fq 'android_global_keys=SystemUI-owned' "$root/input/keyboard-mode.sh"; then
  printf '%s\n' 'Linux-only keyboard focus contract is missing' >&2
  status=1
fi
if grep -R -n --exclude='*.md' -E \
  'AccessibilityService|TYPE_APPLICATION_OVERLAY|onKeyPreIme|INJECT_EVENTS|GLOBAL_ACTION_' \
  "$root/android/app/src/main/java" "$root/android/app/src/main/AndroidManifest.xml"; then
  printf '%s\n' 'Android global keyboard interception/overlay hook found in the ordinary app' >&2
  status=1
fi
if ! grep -Fq 'fedora-shell-guest-android-bridge-v1' "$root/fedora/gnome/install-integration.sh" \
  || ! grep -Fq 'exec /bin/bash "$bridge" "$@"' "$root/fedora/gnome/install-integration.sh" \
  || ! grep -Fq 'FEDORA_GUEST_PROJECT_ROOT:-/opt/fedora-shell' "$root/fedora/gnome/install-integration.sh" \
  || grep -Fq 'install -m 0755 "$bridge_source" /usr/local/bin/fedora-android-bridge' \
    "$root/fedora/gnome/install-integration.sh"; then
  printf '%s\n' 'Fedora-native Android bridge wrapper is missing or still uses the Termux interpreter path' >&2
  status=1
fi
if ! grep -Fq 'mktemp "$RESPONSE_DIR/.${request_id}.response.XXXXXX"' \
  "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq 'mktemp "$BROKER_DIR/.payload.XXXXXX"' \
  "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq 'mktemp "$request_dir/.fedora-request.XXXXXX"' \
  "$root/integration/android-bridge.sh"; then
  printf '%s\n' 'Android bridge temporary files must use mktemp' >&2
  status=1
fi
if ! grep -Fq "trap 'exit 130' INT" "$root/integration/android-bridge-broker.sh" \
  || ! grep -Fq "trap 'exit 130' INT" "$root/scripts/start.sh" \
  || ! grep -Fq "trap 'exit 130' INT" "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'signal cleanup must exit through the single EXIT cleanup path' >&2
  status=1
fi
if ! grep -Fq 'fedora_stop_owned_transports' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'fedora_stop_owned_transports' "$root/scripts/uninstall.sh" \
  || ! grep -Fq 'fedora_stop_owned_transports' "$root/scripts/restore.sh" \
  || ! grep -Fq 'refusing destructive uninstall' "$root/scripts/uninstall.sh" \
  || ! grep -Fq 'refusing destructive restore' "$root/scripts/restore.sh" \
  || ! grep -Fq 'refusing destructive reset' "$root/scripts/reset.sh"; then
  printf '%s\n' 'destructive/recovery commands must stop owned transports first' >&2
  status=1
fi
if ! grep -Fq '&& ! -L "$android_bridge_script"' "$root/scripts/start.sh" \
  || ! grep -Fq 'Refusing to remove symlinked state directory' "$root/scripts/uninstall.sh"; then
  printf '%s\n' 'project-owned broker/state paths must fail closed on symlinks' >&2
  status=1
fi
if ! grep -Fq 'FEDORA_ANDROID_BRIDGE_DIR" \' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'runtime" || -L "$runtime"' "$root/scripts/android-apps.sh"; then
  printf '%s\n' 'Android broker runtime directory must be validated before use' >&2
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
if ! grep -Fq 'disable_unsupported_system_integrations' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'screen-time-limits' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'logind is unavailable in Fedora/PRoot' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'backup_fedora_settings' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'restore_fedora_settings' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'fedora-local-settings.backup' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'PRoot GNOME screen-time/logind compatibility guard is missing' >&2
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
if [[ ! -r "$root/fedora/gnome/pipewire-devkit.conf" ]] \
  || ! grep -Fq 'core.name = pipewire-0' "$root/fedora/gnome/pipewire-devkit.conf" \
  || ! grep -Fq 'libpipewire-module-client-node' "$root/fedora/gnome/pipewire-devkit.conf" \
  || ! grep -Fq 'libpipewire-module-access' "$root/fedora/gnome/pipewire-devkit.conf" \
  || ! grep -Fq 'pipewire-devkit.conf' "$root/scripts/lib/guest-config.sh" \
  || ! grep -Fq 'FEDORA_DEVKIT_PIPEWIRE_CONFIG' "$root/scripts/start.sh"; then
  printf '%s\n' 'isolated Mutter Devkit PipeWire configuration is missing' >&2
  status=1
fi
if ! grep -Fq -- '--no-x11' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'FEDORA_CALENDAR_MODE' "$root/scripts/install.sh" \
  || ! grep -Fq 'PIPEWIRE_CORE=pipewire-0' "$root/scripts/start.sh"; then
  printf '%s\n' 'low-memory nested compositor safeguards are missing' >&2
  status=1
fi
if ! grep -Fq 'DBUS_SYSTEM_BUS_ADDRESS' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'FEDORA_SYSTEM_BUS_MODE' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'start_private_system_bus' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'private_system_bus_process_alive' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'dbus-system-compat.conf' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'system-bus.pid' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'no privileged service activation' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'GIO_USE_VFS' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'portals_disabled_for_bus' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'build_filtered_dbus_service_dir' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'standard_session_servicedirs' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq '<servicedir>' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'dbus-services' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'No standard_session_servicedirs/servicedir/include' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'org.freedesktop.portal' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'suppressed optional service entries' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq '<allow own="*"/>' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'PRoot D-Bus/GVFS compatibility guards are missing' >&2
  status=1
fi
if ! grep -Fq 'FEDORA_SYSTEM_BUS_MODE' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'FEDORA_SYSTEM_BUS_MODE=$FEDORA_SYSTEM_BUS_MODE' "$root/scripts/start.sh" \
  || ! grep -Fq 'FEDORA_SYSTEM_BUS_MODE=private' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'system_bus_mode=' "$root/scripts/diagnostics.sh"; then
  printf '%s\n' 'system-bus compatibility mode is not propagated/diagnosed consistently' >&2
  status=1
fi
if ! grep -Fq 'dbus-update-activation-environment' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'FEDORA_DEVKIT_DEBUG' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'directly spawned GTK viewer' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'update_dbus_activation_environment "$viewer_gdk_backend" "$viewer_wayland_display"' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'export GDK_BACKEND=wayland,x11' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'FEDORA_DEVKIT_VIEWER_TIMEOUT' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'wait_for_stable_process' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'disappeared during readiness' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'official nested Wayland' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'report_devkit_evidence' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'filtered environment' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'devkit_viewer_environment' "$root/scripts/diagnostics.sh" \
  || ! grep -Fq 'FEDORA_DEVKIT_VIEWER_GDK_BACKEND' "$root/fedora/gnome/fedora-session" \
  || grep -Fq 'launch_direct_devkit_viewer' "$root/fedora/gnome/fedora-session" \
  || grep -Fq 'Started direct mutter-devkit viewer fallback' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'Mutter Devkit backend/debug evidence guard is missing or has an invalid standalone fallback' >&2
  status=1
fi
if ! grep -Fq 'fedora-shell-mutter-devkit-wrapper-v1' "$root/fedora/gnome/mutter-devkit-wrapper" \
  || ! grep -Fq 'org.gnome.Mutter.Devkit' "$root/fedora/gnome/mutter-devkit-wrapper" \
  || ! grep -Fq 'Properties.Get' "$root/fedora/gnome/mutter-devkit-wrapper" \
  || ! grep -Fq ' Env ' "$root/fedora/gnome/mutter-devkit-wrapper" \
  || ! grep -Fq 'gdbus' "$root/fedora/gnome/mutter-devkit-wrapper" \
  || ! grep -Fq 'mutter-devkit.real' "$root/fedora/gnome/mutter-devkit-wrapper" \
  || ! grep -Fq 'FEDORA_DEVKIT_ACTIVATION_TIMEOUT' "$root/fedora/gnome/mutter-devkit-wrapper" \
  || ! grep -Fq 'export GDK_BACKEND="$viewer_backend"' "$root/fedora/gnome/mutter-devkit-wrapper" \
  || ! grep -Fq 'install_mutter_devkit_wrapper' "$root/fedora/gnome/install-integration.sh" \
  || ! grep -Fq 'restore-mutter-devkit.sh' "$root/fedora/gnome/install-integration.sh" \
  || ! grep -Fq 'restore_mutter_devkit_helper' "$root/fedora/rootfs/install-gnome.sh" \
  || ! grep -Fq 'fedora-shell-mutter-devkit-restore-v1' "$root/fedora/rootfs/restore-mutter-devkit.sh" \
  || ! grep -Fq 'restore-mutter-devkit' "$root/scripts/update.sh" \
  || ! grep -Fq 'fedora-shell-mutter-devkit-real-v1' "$root/fedora/gnome/install-integration.sh"; then
  printf '%s\n' 'reversible Fedora-only Mutter Devkit activation shim is missing' >&2
  status=1
fi
if ! grep -Fq 'android:path="/launch"' "$root/android/app/src/main/AndroidManifest.xml" \
  || ! grep -Fq 'android:host="android"' "$root/android/app/src/main/AndroidManifest.xml"; then
  printf '%s\n' 'Android launch deep-link must be constrained to the project path' >&2
  status=1
fi
if grep -Fq -- '--unset=WAYLAND_DISPLAY' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'unsupported dbus-update-activation-environment unset option remains' >&2
  status=1
fi
if ! grep -Fq 'prepare_guest_systemd_marker' "$root/scripts/start.sh" \
  || ! grep -Fq 'restore_guest_systemd_marker' "$root/scripts/start.sh" \
  || ! grep -Fq 'FEDORA_SYSTEMD_MARKER_MASKED' "$root/scripts/start.sh" \
  || ! grep -Fq 'guest_systemd_marker_evidence' "$root/scripts/diagnostics.sh" \
  || ! grep -Fq 'guest_session_marker_backup' "$root/scripts/diagnostics.sh" \
  || ! grep -Fq 'session_backup=/tmp/fedora-runtime/systemd-seats-marker' "$root/scripts/stop.sh" \
  || ! grep -Fq 'restore_guest_fedora_settings' "$root/scripts/stop.sh" \
  || ! grep -Fq 'FEDORA_MARKER_STATE=restored' "$root/scripts/stop.sh"; then
  printf '%s\n' 'PRoot stale systemd marker preflight/restore evidence is missing' >&2
  status=1
fi
if ! grep -Fq 'if (!x11Opened)' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java"; then
  printf '%s\n' 'GUI must not start a headless Fedora session without a visible X11 Activity' >&2
  status=1
fi
if grep -Fq 'hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars())' \
  "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || grep -Fq 'View.SYSTEM_UI_FLAG_HIDE_NAVIGATION' \
  "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'mandatorySystemGestures' \
  "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'Safe navigation hint' "$root/scripts/start.sh" \
  || ! grep -Fq 'FEDORA_TERMUX_X11_FULLSCREEN:=0' "$root/scripts/lib/common.sh"; then
  printf '%s\n' 'Android bottom navigation safe-area handling is missing or hides navigation' >&2
  status=1
fi
if ! grep -Fq 'linux_mode_stop_requested' "$root/scripts/start.sh" \
  || ! grep -Fq 'FEDORA_LINUX_MODE_STOP_REQUEST' "$root/scripts/start.sh" \
  || ! grep -Fq 'FEDORA_LINUX_MODE_STOP_REQUEST_HOST' "$root/scripts/start.sh" \
  || ! grep -Fq 'MODE_STOP_REQUEST' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'MODE_GUEST_STOP_REQUEST' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'MODE_RUNTIME_HOST_DIR' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'wait_for_start_ready' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'max_start_attempts=2' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'session_ready=' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'memory-after.json' "$root/scripts/linux-mode.sh"; then
  printf '%s\n' 'Linux Mode transition race/readiness guard is missing' >&2
  status=1
fi
if ! grep -Fq '[[ -f "$MODE_STOP_REQUEST" && ! -L "$MODE_STOP_REQUEST" ]]' \
  "$root/scripts/linux-mode.sh" \
  || ! grep -Fq '[[ -f "$FEDORA_LINUX_MODE_STOP_REQUEST" \' \
    "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq '[[ -f "$FEDORA_LINUX_MODE_STOP_REQUEST_HOST" \' \
    "$root/scripts/start.sh"; then
  printf '%s\n' 'Linux Mode stop requests must reject symlinked state paths' >&2
  status=1
fi
if ! grep -Fq 'active without a verified Wayland session' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'refusing to start a second Linux session' "$root/scripts/linux-mode.sh"; then
  printf '%s\n' 'stale active-container readiness guard is missing' >&2
  status=1
fi
if ! grep -Fq 'safe no-op' "$root/integration/boot/fedora-shell" \
  || grep -Fq 'start.sh" --reconnect' "$root/integration/boot/fedora-shell" \
  || ! grep -Fq 'Replaced the old hidden Termux:Boot launcher' "$root/scripts/install.sh"; then
  printf '%s\n' 'Termux:Boot must not start a hidden Fedora workload' >&2
  status=1
fi
if grep -Fq 'ephemeral PRoot bind mask' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'stale systemd marker wording must describe the actual rename backup' >&2
  status=1
fi
if grep -Fq 'send_destination_prefix' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'portal D-Bus policy must not broadly deny GNOME/Mutter requests' >&2
  status=1
fi
if grep -Fq 'Exec=/usr/bin/false' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'optional D-Bus services must be filtered, not replaced with failing stubs' >&2
  status=1
fi
if grep -Fq 'source "$session_state_host"' "$root/scripts/start.sh"; then
  printf '%s\n' 'start.sh must not reuse stale Wayland session metadata' >&2
  status=1
fi

if ! grep -Fq 'FEDORA_LINUX_MODE_PROFILE' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'FEDORA_LINUX_MODE_PROFILE' "$root/scripts/install.sh" \
  || ! grep -Fq 'linux-mode.sh' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/BridgeClient.java"; then
  printf '%s\n' 'Linux Mode controller integration is missing' >&2
  status=1
fi
if ! grep -Fq 'Первоначальная настройка' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'ACTION_HOME_SETTINGS' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'category android:name="android.intent.category.HOME"' "$root/android/app/src/main/AndroidManifest.xml" \
  || ! grep -Fq 'android:exported="false"' "$root/android/app/src/main/AndroidManifest.xml" \
  || ! grep -A4 -F '<receiver' "$root/android/app/src/main/AndroidManifest.xml" \
    | grep -Fq 'android:exported="false"'; then
  printf '%s\n' 'first-run GUI/Home setup is missing' >&2
  status=1
fi
if ! grep -Fq 'requestModeStatus' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/BridgeClient.java" \
  || ! grep -Fq 'requestModeStatusToken' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/BridgeClient.java" \
  || ! grep -Fq 'requestMemory' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/BridgeClient.java" \
  || ! grep -Fq 'requestMemoryToken' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/BridgeClient.java" \
  || ! grep -Fq 'RUN_COMMAND_PENDING_INTENT' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/BridgeClient.java" \
  || ! grep -Fq 'EXTRA_REQUEST_KIND' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/CommandResultService.java" \
  || ! grep -Fq 'EXTRA_REQUEST_TOKEN' "$root/android/app/src/main/java/com/pluseight8/fedorashell/bridge/CommandResultService.java" \
  || ! grep -Fq 'Previous Linux Mode did not exit cleanly' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'statusProbeGeneration' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'memoryProbeGeneration' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'showMemoryReportDialog' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'CommandResultService' "$root/android/app/src/main/AndroidManifest.xml"; then
  printf '%s\n' 'Home crash-recovery status callback is missing' >&2
  status=1
fi
if ! grep -Fq '"usage": "reporting-only"' "$root/config/android-memory-allowlist.json" \
  || ! grep -Fq '"androidChangesApplied": false' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'android_changes_applied=false' "$root/scripts/linux-mode.sh" \
  || ! grep -Fq 'cachedKiB' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'swapFreeKiB' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'gpu' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'key ":"' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'allowlist_array' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq '"mode": "reporting-only"' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'recommendation_array' "$root/integration/android-memory-governor.sh"; then
  printf '%s\n' 'read-only Android memory policy evidence is missing' >&2
  status=1
fi
if ! grep -Fq 'thirdPartyPackageCountReadable' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'swapReadable' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'systemProcessCountReadable' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'The Android third-party package count was unavailable' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'collect_zram_state' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'sysfs_bytes_to_kib' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq '"ramPlus"' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'zramPhysicalUsedKiB' "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq 'setting-unknown' "$root/integration/android-memory-governor.sh"; then
  printf '%s\n' 'memory report readability flags are missing' >&2
  status=1
fi
if ! grep -Fq 'android_ramplus_snapshot' "$root/scripts/diagnostics.sh" \
  || ! grep -Fq 'readonly_sysfs_bytes_to_kib' "$root/scripts/diagnostics.sh" \
  || ! grep -Fq 'ramplus_setting=not-readable' "$root/scripts/diagnostics.sh" \
  || ! grep -Fq 'ramplus_note=zRAM/swap observations are indirect' "$root/scripts/diagnostics.sh"; then
  printf '%s\n' 'read-only RAM Plus diagnostic evidence is missing' >&2
  status=1
fi
if grep -R -n --exclude='*.md' -E \
  'appops[[:space:]]+set|am[[:space:]]+force-stop|pm[[:space:]]+(disable|enable|clear)|settings[[:space:]]+put|cmd[[:space:]]+package[[:space:]]+set-stopped-state|(^|[[:space:]])pkill([[:space:]]|$)|(^|[[:space:]])killall([[:space:]]|$)|drop_caches|(^|[[:space:]])sysctl([[:space:]]|$)' \
  "$root/scripts/linux-mode.sh" "$root/integration/android-memory-governor.sh" "$root/android"; then
  printf '%s\n' 'Android policy-changing command found in the controller/monitor' >&2
  status=1
fi
if grep -R -n --exclude='*.md' -E \
  'termux-x11-preference[[:space:]]+[^[:space:]]+=|termux-(brightness|clipboard-set|vibrate)|setStreamVolume|setMediaVolume|vibrate\(' \
  "$root/scripts" "$root/integration" "$root/android"; then
  printf '%s\n' 'Android device-setting mutator found in the read-only bridge' >&2
  status=1
fi
# The one Samsung package below is not an application allowlist: it is the
# optional, documented Device Care deep-sleep navigation target. All other
# firmware-dependent package maps remain forbidden.
if grep -R -n --exclude='*.md' -E \
  'APP_PACKAGES|com\.(samsung|sec)\.|com\.google\.|com\.android\.(chrome|vending)' \
  "$root/android/app/src/main/java" "$root/integration/android-apps.conf" \
  | grep -Ev 'com\.samsung\.android\.lool|ACTION_OPEN_CHECKABLE_LISTACTIVITY'; then
  printf '%s\n' 'Android APK must not hard-code firmware-dependent app package maps' >&2
  status=1
fi
if ! grep -Fq 'intent:android.settings.SETTINGS' "$root/integration/android-apps.conf" \
  || ! grep -Fq 'valid_intent_action' "$root/integration/android-bridge.sh" \
  || ! grep -Fq 'X-Fedora-Shell-Target' "$root/fedora/gnome/install-integration.sh" \
  || grep -Fq 'X-Fedora-Shell-Package' "$root/fedora/gnome/install-integration.sh"; then
  printf '%s\n' 'generic intent/user-selected Android target integration is missing' >&2
  status=1
fi
if ! grep -Fq 'isSelectedHome' "$root/android/app/src/main/java/com/pluseight8/fedorashell/boot/BootReceiver.java" \
  || ! grep -Fq 'isRoleHeld' "$root/android/app/src/main/java/com/pluseight8/fedorashell/boot/BootReceiver.java" \
  || ! grep -Fq 'getLaunchIntentForPackage("com.termux")' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java"; then
  printf '%s\n' 'Home-gated boot behavior and first-run Termux guidance are missing' >&2
  status=1
fi
if ! grep -Fq 'android_app_bridge_enabled' "$root/scripts/start.sh" \
  || ! grep -Fq 'no broker process will be started' "$root/scripts/start.sh" \
  || ! grep -Fq 'verified_wayland_session' "$root/scripts/start.sh" \
  || ! grep -Fq 'refusing to start a second GNOME session' "$root/scripts/start.sh"; then
  printf '%s\n' 'Android bridge low-memory disable/reconnect readiness guard is missing' >&2
  status=1
fi
if ! grep -Fq 'atomic_install_file' "$root/fedora/gnome/install-integration.sh" \
  || ! grep -Fq 'atomic_replace_from_stdin' "$root/fedora/gnome/install-integration.sh" \
  || ! grep -Fq 'unsafe Fedora runtime path' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'Refusing an unsafe private D-Bus service directory' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'runtime/install atomicity and symlink guards are missing' >&2
  status=1
fi
if ! grep -Fq 'session_path_parents_safe "$service_dir"' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'Refusing unexpected entry in private D-Bus service directory' "$root/fedora/gnome/fedora-session" \
  || grep -Fq 'rm -rf -- "$service_dir"' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'refusing unsafe Fedora-local settings backup' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'pipewire_process_alive' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq '! -L "$FEDORA_SESSION_RUNTIME/pipewire-0"' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'if [[ -L "$marker" || -L "$systemd_marker_backup" ]]' "$root/fedora/gnome/fedora-session" \
  || ! grep -Fq 'if [ -L "$marker" ] || [ -L "$backup" ]; then' "$root/scripts/start.sh" \
  || ! grep -Fq 'FEDORA_MARKER_STATE=unsafe' "$root/scripts/start.sh" \
  || ! grep -Fq 'if [ -L "$candidate" ] || [ -L "$marker" ]; then' "$root/scripts/stop.sh"; then
  printf '%s\n' 'Fedora runtime service/socket cleanup must be narrow and symlink-safe' >&2
  status=1
fi
if ! grep -Fq '[[ ! -e "$path/.git" ]]' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'find "$source_root/$item" -type l' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'find "$target_root/$item" -type l' "$root/scripts/lib/common.sh" \
  || ! grep -Fq 'fedora_install_root_path_is_safe "$install_root"' "$root/scripts/uninstall.sh" \
  || ! grep -Fq 'remove_install_tree' "$root/scripts/uninstall.sh" \
  || grep -Fq 'rm -rf -- "$install_root"' "$root/scripts/uninstall.sh" \
  || ! grep -Fq 'Backup must be a regular, non-symlink file' "$root/scripts/restore.sh"; then
  printf '%s\n' 'checkout/install-root and destructive archive/tree guards are missing' >&2
  status=1
fi
if grep -Fq 'fedora_die "Termux:X11 Android APK' "$root/scripts/start.sh" \
  || ! grep -Fq 'The Termux:X11 socket check remains authoritative' "$root/scripts/start.sh" \
  || ! grep -Fq 'not-confirmed' "$root/scripts/linux-mode.sh"; then
  printf '%s\n' 'Android 16 restricted package-query fallback is missing' >&2
  status=1
fi
if ! grep -Fq 'showRamPlusGuidance' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'RAM Plus — read-only guidance' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'android.ramPlus.setting=not-readable' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java" \
  || ! grep -Fq 'Обслуживание устройства' "$root/android/app/src/main/java/com/pluseight8/fedorashell/MainActivity.java"; then
  printf '%s\n' 'RAM Plus read-only GUI guidance is missing' >&2
  status=1
fi
if grep -R -n --exclude='*.md' -E 'FEDORA_ANDROID_APPOPS|FEDORA_MAXIMUM_LINUX_FORCE_STOP|FEDORA_ANDROID_MEMORY_PROFILE' \
  "$root/scripts" "$root/integration" "$root/android"; then
  printf '%s\n' 'obsolete Android policy controls must not remain in executable code' >&2
  status=1
fi

if ! grep -Fq "app_system=\"\$(dumpsys_field_kib \"\$dump_file\" 'System')\"" \
  "$root/integration/android-memory-governor.sh" \
  || ! grep -Fq '[[ -f "$report" && ! -L "$report" && -r "$report" ]]' \
  "$root/integration/android-memory-governor.sh"; then
  printf '%s\n' 'memory attribution/symlink guards are missing' >&2
  status=1
fi

# Keep the no-Android-mutation contract broad enough to cover future helper
# scripts, while allowing the explicitly user-triggered `am start` bridge and
# Fedora-local `gsettings` tuning. This is a source audit, not a runtime claim.
if grep -R -n --exclude-dir=.git --exclude='*.md' --exclude='tests/static.sh' -E \
  '(^|[[:space:];|&])settings[[:space:]]+(put|delete)|(^|[[:space:];|&])appops[[:space:]]+set|(^|[[:space:];|&])am[[:space:]]+force-stop|(^|[[:space:];|&])pm[[:space:]]+(disable|enable|clear)|forceStopPackage|setComponentEnabledSetting|DevicePolicyManager|Settings\.(Secure|Global|System)\.(put|delete)|drop_caches|(^|[[:space:];|&])sysctl([[:space:];|&]|$)' \
  "$root/scripts" "$root/integration" "$root/android"; then
  printf '%s\n' 'Android mutation API/command found outside the approved read-only/user-navigation surface' >&2
  status=1
fi

if [[ -r "$root/tests/android-bridge.sh" ]] \
  && ! bash "$root/tests/android-bridge.sh" >/dev/null 2>&1; then
  printf '%s\n' 'Android bridge fallback protocol test failed' >&2
  status=1
fi
if [[ -r "$root/tests/safety.sh" ]] \
  && ! bash "$root/tests/safety.sh" >/dev/null 2>&1; then
  printf '%s\n' 'path/atomic-write safety regression test failed' >&2
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
