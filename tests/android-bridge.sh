#!/usr/bin/env bash
set -Eeuo pipefail

# Host-side protocol test. It never calls Android: the fake `am` and
# `termux-open-url` below model the two Android 16 paths that the client must
# distinguish. The test is intentionally independent of Termux and an Android
# SDK, so it can run in CI on an ordinary Linux host.

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$FAKE_BIN" "$TEST_ROOT/home"

cat > "$FAKE_BIN/am" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *com.example.missing* ]]; then
  printf '%s\n' 'Error: Activity not started, unable to resolve Intent'
  exit 1
fi
printf '%s\n' 'SecurityException: Permission Denial: background activity start denied'
exit 1
EOF

cat > "$FAKE_BIN/termux-open-url" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$FEDORA_TEST_URI_FILE"
EOF

chmod 0755 "$FAKE_BIN/am" "$FAKE_BIN/termux-open-url"

output="$(PATH="$FAKE_BIN:$PATH" \
  FEDORA_TEST_URI_FILE="$TEST_ROOT/uri" \
  FEDORA_ANDROID_BRIDGE_DIR="$TEST_ROOT/no-broker" \
  HOME="$TEST_ROOT/home" \
  bash "$ROOT/integration/android-bridge.sh" launch-package com.example.alpha 2>"$TEST_ROOT/alpha.err")"
grep -Fq 'Android controller launch requested for com.example.alpha' <<< "$output"
grep -Fxq 'fedora-shell://android/launch?package=com.example.alpha' "$TEST_ROOT/uri"

if PATH="$FAKE_BIN:$PATH" \
  FEDORA_TEST_URI_FILE="$TEST_ROOT/uri-missing" \
  FEDORA_ANDROID_BRIDGE_DIR="$TEST_ROOT/no-broker" \
  HOME="$TEST_ROOT/home" \
  bash "$ROOT/integration/android-bridge.sh" launch-package com.example.missing \
  >"$TEST_ROOT/missing.out" 2>"$TEST_ROOT/missing.err"; then
  printf '%s\n' 'resolver failure was incorrectly reported as success' >&2
  exit 1
fi
[[ ! -e "$TEST_ROOT/uri-missing" ]]
grep -Fq 'Activity not started' "$TEST_ROOT/missing.err"

# Catalog tests model Android's read-only package inventory and launcher
# resolver. `all` must include a preinstalled/system launchable package, while
# the default `user` scope must retain the third-party-only contract.
CATALOG_BIN="$TEST_ROOT/catalog-bin"
mkdir -p "$CATALOG_BIN"
cat > "$CATALOG_BIN/pm" <<'EOF'
#!/usr/bin/env bash
if [[ "${FEDORA_TEST_DENY_PACKAGE_LIST:-0}" == 1 ]]; then
  printf '%s\n' 'SecurityException: package list denied' >&2
  exit 1
fi
if [[ "$1" == list && "$2" == packages && "$3" == -3 ]]; then
  printf '%s\n' 'package:com.example.user'
  exit 0
fi
if [[ "$1" == list && "$2" == packages ]]; then
  printf '%s\n' 'package:com.example.user'
  printf '%s\n' 'package:com.example.system'
  exit 0
fi
exit 1
EOF
cat > "$CATALOG_BIN/cmd" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == package && "$2" == list && "$3" == packages* ]]; then
  if [[ "${FEDORA_TEST_DENY_PACKAGE_LIST:-0}" == 1 ]]; then exit 1; fi
  printf '%s\n' 'package:com.example.user'
  printf '%s\n' 'package:com.example.system'
  exit 0
fi
if [[ "$1" == package && "$2" == query-activities* ]]; then
  printf '%s\n' 'com.example.user/com.example.UserActivity'
  printf '%s\n' 'com.example.system/com.example.SystemActivity'
  exit 0
fi
exit 1
EOF
chmod 0755 "$CATALOG_BIN/pm" "$CATALOG_BIN/cmd"

user_catalog="$(PATH="$CATALOG_BIN:$PATH" \
  FEDORA_ANDROID_BRIDGE_DIR="$TEST_ROOT/no-broker-user" \
  HOME="$TEST_ROOT/home" \
  bash "$ROOT/integration/android-bridge.sh" list-apps)"
grep -Fq 'com.example.user|com.example.user/com.example.UserActivity' <<< "$user_catalog"
if grep -Fq 'com.example.system|' <<< "$user_catalog"; then
  printf '%s\n' 'user Android catalog widened into system packages' >&2
  exit 1
fi

all_catalog="$(PATH="$CATALOG_BIN:$PATH" \
  FEDORA_ANDROID_BRIDGE_DIR="$TEST_ROOT/no-broker-all" \
  HOME="$TEST_ROOT/home" \
  bash "$ROOT/integration/android-bridge.sh" list-apps --all)"
grep -Fq 'com.example.user|com.example.user/com.example.UserActivity' <<< "$all_catalog"
grep -Fq 'com.example.system|com.example.system/com.example.SystemActivity' <<< "$all_catalog"

# Android 16/vendor variant: package enumeration is denied, but the resolver
# remains readable. `all` must use the resolver-only path rather than fail or
# invent package state.
resolver_only_catalog="$(PATH="$CATALOG_BIN:$PATH" \
  FEDORA_TEST_DENY_PACKAGE_LIST=1 \
  FEDORA_ANDROID_BRIDGE_DIR="$TEST_ROOT/no-broker-resolver" \
  HOME="$TEST_ROOT/home" \
  bash "$ROOT/integration/android-bridge.sh" list-apps --all)"
grep -Fq 'com.example.system|com.example.system/com.example.SystemActivity' <<< "$resolver_only_catalog"

printf '%s\n' 'android bridge fallback checks passed'
