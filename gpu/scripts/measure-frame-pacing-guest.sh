#!/usr/bin/env bash
set -Eeuo pipefail

# Marker: fedora-shell-frame-pacing-guest-v1
DURATION="${FEDORA_FRAME_SECONDS:-10}"
[[ "$DURATION" =~ ^[0-9]+$ ]] || DURATION=10
printf 'fedora-shell-frame-pacing-guest-v1\n'
printf 'duration_seconds=%s\n' "$DURATION"
printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'DISPLAY=%s\n' "${DISPLAY:-}"
printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-}"
printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-}"
printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"

if command -v glmark2-wayland >/dev/null 2>&1; then
  printf '\n[glmark2-wayland proxy run]\n'
  set +e
  timeout "$DURATION" glmark2-wayland 2>&1 | sed -n '1,240p'
  rc=${PIPESTATUS[0]}
  set -e
  printf '[exit=%s]\n' "$rc"
elif command -v weston-simple-egl >/dev/null 2>&1; then
  printf '\n[weston-simple-egl proxy run]\n'
  set +e
  timeout "$DURATION" weston-simple-egl 2>&1 | sed -n '1,160p'
  rc=${PIPESTATUS[0]}
  set -e
  printf '[exit=%s]\n' "$rc"
else
  printf '\nNo Wayland frame client is installed; install glmark2 or weston-demo packages only after the base session is stable.\n'
fi

printf '\nINTERPRETATION=This is a client/compositor proxy measurement. It is not proof of Android panel presentation at 120 Hz.\n'
