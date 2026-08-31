#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-bootstrap-v1

REPO_URL="https://github.com/pluseight8/sgts11u-linux-fedora.git"
REPO_REF="main"
TARGET_DIR="${HOME:-}/fedora-galaxy"
RUN_INSTALL=1
INSTALL_ARGS=()

usage() {
  cat >&2 <<'EOF'
Usage: bootstrap.sh [OPTIONS]

Downloads or reuses the Fedora Shell checkout, installs Git non-interactively
when needed, then runs the project installer.

Options:
  --dir DIRECTORY         checkout location (default: $HOME/fedora-galaxy)
  --ref REF               branch or tag to clone (default: main)
  --no-install            only prepare the checkout
  --yes                   pass --yes to scripts/install.sh
  --allow-unknown-device pass --allow-unknown-device to the installer
  --enable-boot           pass --enable-boot to the installer
  --skip-x11-package      pass --skip-x11-package to the installer
  --min-free-gib N        pass --min-free-gib N to the installer
  -h, --help              show this help

This bootstrap intentionally does not call termux-setup-storage because that
command is interactive when ~/storage already exists. Run it separately after
the bootstrap if shared Android storage is needed.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dir)
      (( $# >= 2 )) || { usage; exit 64; }
      TARGET_DIR="$2"
      shift 2
      ;;
    --ref)
      (( $# >= 2 )) || { usage; exit 64; }
      REPO_REF="$2"
      shift 2
      ;;
    --no-install)
      RUN_INSTALL=0
      shift
      ;;
    --yes|--allow-unknown-device|--enable-boot|--skip-x11-package)
      INSTALL_ARGS+=("$1")
      shift
      ;;
    --min-free-gib)
      (( $# >= 2 )) || { usage; exit 64; }
      INSTALL_ARGS+=("$1" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      printf 'Unknown option: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done

if [[ -z "${HOME:-}" ]]; then
  printf '%s\n' 'HOME is not set; open a normal Termux shell first.' >&2
  exit 1
fi
if [[ -z "${TERMUX_VERSION:-}" && "${PREFIX:-}" != /data/data/*/files/usr ]]; then
  printf '%s\n' 'This bootstrap must run inside Termux on Android.' >&2
  exit 1
fi
if [[ "$(id -u)" == 0 ]]; then
  printf '%s\n' 'Root shell detected; Fedora Shell intentionally runs as the ordinary Termux user.' >&2
  exit 1
fi
command -v pkg >/dev/null 2>&1 || {
  printf '%s\n' 'Termux pkg is unavailable; use the official Termux app.' >&2
  exit 1
}
command -v git >/dev/null 2>&1 || {
  printf '%s\n' 'Git is missing; installing it with non-interactive Termux pkg flags.' >&2
  pkg update -y || {
    printf '%s\n' 'Termux package update failed. Run termux-change-repo and retry.' >&2
    exit 1
  }
  # Termux is rolling-release and does not support partial upgrades. Upgrade
  # the existing environment before adding Git to avoid mixed shared libs.
  pkg upgrade -y || {
    printf '%s\n' 'Termux package upgrade failed. Run apt --fix-broken install -y, then retry.' >&2
    exit 1
  }
  pkg install -y git || {
    printf '%s\n' 'Git installation failed. Run termux-change-repo and retry.' >&2
    exit 1
  }
}
command -v git >/dev/null 2>&1 || {
  printf '%s\n' 'Git is still unavailable after pkg install.' >&2
  exit 1
}

if [[ -e "$TARGET_DIR" || -L "$TARGET_DIR" ]]; then
  [[ -d "$TARGET_DIR" && ! -L "$TARGET_DIR" ]] || {
    printf 'Refusing to use non-directory or symlink checkout path: %s\n' "$TARGET_DIR" >&2
    exit 1
  }
  if [[ -d "$TARGET_DIR/.git" ]]; then
    remote_url="$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)"
    case "$remote_url" in
      "$REPO_URL"|"https://github.com/pluseight8/sgts11u-linux-fedora"|"git@github.com:pluseight8/sgts11u-linux-fedora.git") ;;
      *)
        printf 'Existing checkout has an unexpected origin: %s\n' "${remote_url:-<none>}" >&2
        exit 1
        ;;
    esac
    current_branch="$(git -C "$TARGET_DIR" symbolic-ref --short -q HEAD || true)"
    if [[ "$current_branch" == "$REPO_REF" ]]; then
      if [[ -n "$(git -C "$TARGET_DIR" status --porcelain 2>/dev/null)" ]]; then
        printf 'Existing checkout has local changes; keeping it without pull: %s\n' "$TARGET_DIR" >&2
      else
        printf 'Updating existing Fedora Shell checkout: %s\n' "$TARGET_DIR"
        git -C "$TARGET_DIR" pull --ff-only
      fi
    else
      printf 'Using existing checkout on branch %s; no pull performed: %s\n' \
        "${current_branch:-detached HEAD}" "$TARGET_DIR"
    fi
  else
    if [[ -n "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
      printf 'Refusing to clone into a non-empty directory without Git metadata: %s\n' "$TARGET_DIR" >&2
      exit 1
    fi
    git clone --depth=1 --branch "$REPO_REF" "$REPO_URL" "$TARGET_DIR"
  fi
else
  parent_dir="$(dirname -- "$TARGET_DIR")"
  mkdir -p "$parent_dir"
  git clone --depth=1 --branch "$REPO_REF" "$REPO_URL" "$TARGET_DIR"
fi

if (( RUN_INSTALL )); then
  [[ -x "$TARGET_DIR/scripts/install.sh" ]] || chmod 700 "$TARGET_DIR/scripts/install.sh"
  exec "$TARGET_DIR/scripts/install.sh" "${INSTALL_ARGS[@]}"
fi

printf '%s\n' "Checkout ready: $TARGET_DIR"
printf '%s\n' "Run: $TARGET_DIR/scripts/install.sh"
