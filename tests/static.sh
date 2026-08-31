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
if grep -Fxq 'xorg-x11-server-utils' "$root/fedora/packages/gnome-packages.txt"; then
  printf '%s\n' 'unavailable xorg-x11-server-utils must not be a required package' >&2
  status=1
fi
if ! grep -Fq -- '--devkit' "$root/fedora/gnome/fedora-session"; then
  printf '%s\n' 'GNOME 49+ Devkit launch path is missing' >&2
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
