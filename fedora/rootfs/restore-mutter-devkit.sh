#!/usr/bin/env bash
set -Eeuo pipefail

# Marker: fedora-shell-mutter-devkit-restore-v1
#
# Fedora-only package-maintenance helper. The integration shim temporarily
# occupies the exact libexec path that MetaMdk launches; restore the saved RPM
# executable before dnf verifies or replaces that path. Nothing here reaches
# Android, One UI, package state or system processes.

[[ "$(id -u)" == 0 ]] || {
  printf '%s\n' 'Mutter Devkit package helper requires Fedora guest root.' >&2
  exit 1
}

target=/usr/libexec/mutter-devkit
real=/usr/local/libexec/fedora-shell/mutter-devkit.real
owner=/usr/local/libexec/fedora-shell/mutter-devkit.real.owner

if [[ -f "$target" && ! -L "$target" ]] \
  && grep -Fq 'fedora-shell-mutter-devkit-wrapper-v1' "$target" 2>/dev/null; then
  if [[ ! -x "$real" || ! -f "$real" || -L "$real" \
    || ! -f "$owner" || -L "$owner" ]] \
    || ! grep -Fq 'fedora-shell-mutter-devkit-real-v1' "$owner"; then
    printf '%s\n' 'Mutter Devkit wrapper is active but its trusted original is missing; refusing package maintenance.' >&2
    exit 1
  fi
  temporary="$(mktemp /usr/libexec/.fedora-mutter-devkit.XXXXXX)"
  if ! install -m 0755 "$real" "$temporary"; then
    rm -f -- "$temporary"
    exit 1
  fi
  [[ ! -L "$target" ]] || {
    rm -f -- "$temporary"
    exit 1
  }
  mv -f -- "$temporary" "$target"
  printf '%s\n' 'Restored the original Mutter Devkit binary before the Fedora package transaction.' >&2
fi
