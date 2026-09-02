#!/usr/bin/env bash
set -Eeuo pipefail

# Small host-side regression tests for the path and atomic-write guards. The
# test uses an explicitly created temporary directory and never touches the
# real HOME, checkout or Android filesystem.
root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_home="$(mktemp -d "${TMPDIR:-/tmp}/fedora-shell-safety.XXXXXX")"
trap 'rm -rf -- "$test_home"' EXIT
mkdir -p "$test_home/reports" "$test_home/data"
printf '%s\n' 'existing' > "$test_home/reports/existing.txt"
ln -s "$test_home/reports/existing.txt" "$test_home/reports/report-link.txt"

HOME="$test_home" FEDORA_STATE_DIR="$test_home/state" \
  bash -c '
    set -Eeuo pipefail
    source "$1/scripts/lib/common.sh"

    must_fail() {
      if "$@"; then
        printf "expected failure: %s\n" "$*" >&2
        exit 1
      fi
    }

    must_pass() {
      "$@" || {
        printf "expected success: %s\n" "$*" >&2
        exit 1
      }
    }

    must_fail fedora_path_is_safe "$HOME/data/../outside"
    must_fail fedora_path_is_safe "$HOME/data/./outside"
    must_fail fedora_user_data_path_is_safe "$FEDORA_PROJECT_ROOT"
    must_pass fedora_user_data_path_is_safe "$HOME/data"
    must_pass fedora_report_path_is_safe "$HOME/reports/new.txt"
    must_pass fedora_report_path_is_safe "$HOME/reports/existing.txt"
    must_fail fedora_report_path_is_safe "$HOME/reports/report-link.txt"

    must_pass fedora_atomic_write "$HOME/reports/atomic.txt" 600 <<EOF
atomic content
EOF
    [[ "$(<"$HOME/reports/atomic.txt")" == "atomic content" ]]
    must_fail fedora_atomic_write "$HOME/reports/report-link.txt" 600 <<EOF
must not follow a link
EOF
  ' bash "$root"

printf '%s\n' 'safety checks passed'
