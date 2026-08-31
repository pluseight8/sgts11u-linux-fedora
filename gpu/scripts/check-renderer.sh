#!/usr/bin/env bash
set -Eeuo pipefail

# Marker: fedora-shell-renderer-check-v1
printf 'fedora-shell-renderer-check-v1\n'
printf 'uname_m=%s\n' "$(uname -m 2>/dev/null || true)"
printf 'DISPLAY=%s\n' "${DISPLAY:-}"
printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-}"
printf 'XDG_RUNTIME_DIR=%s\n' "${XDG_RUNTIME_DIR:-}"
printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"
printf 'GALLIUM_DRIVER=%s\n' "${GALLIUM_DRIVER:-auto}"

software_renderer=0
run_probe() {
  local name="$1"
  shift
  printf '\n[%s]\n' "$name"
  if command -v "$1" >/dev/null 2>&1; then
    set +e
    "$@" 2>&1 | sed -n '1,120p'
    local rc=${PIPESTATUS[0]}
    set -e
    printf '[exit=%s]\n' "$rc"
  else
    printf 'absent\n'
  fi
}

if command -v glxinfo >/dev/null 2>&1; then
  glx_output="$(glxinfo -B 2>&1 || true)"
  printf '\n[glxinfo -B]\n%s\n' "$glx_output" | sed -n '1,160p'
  if grep -Eiq 'llvmpipe|softpipe|lavapipe|software rasterizer' <<< "$glx_output"; then
    software_renderer=1
  fi
else
  printf '\n[glxinfo -B]\nabsent\n'
fi

run_probe eglinfo eglinfo
run_probe wayland-info wayland-info
run_probe vulkaninfo vulkaninfo --summary

if (( software_renderer )); then
  printf '\nRESULT=software-renderer\n'
else
  printf '\nRESULT=not-proven\n'
fi
printf 'NOTE=Only a real non-software renderer plus a successful GNOME Wayland session counts as GPU acceleration.\n'
exit 0
