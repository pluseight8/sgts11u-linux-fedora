#!/usr/bin/env bash
set -Eeuo pipefail

# Marker: fedora-shell-wayland-input-smoke-v1
printf 'fedora-shell-wayland-input-smoke-v1\n'
printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"
printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-}"
printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-}"
if command -v wayland-info >/dev/null 2>&1; then
  wayland-info 2>&1 | sed -n '1,240p' || true
else
  printf 'wayland-info is absent\n'
fi
printf 'NOTE=Touch and S Pen pressure/tilt require a real device event test; this is only a protocol smoke check.\n'
