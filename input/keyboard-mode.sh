#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# Marker: fedora-shell-keyboard-mode-v1
#
# This helper is deliberately observational. Android does not expose a public
# ordinary-app API for globally stealing protected hardware shortcuts from
# SystemUI. Linux Mode therefore relies on the normal focused-Activity path:
# Android input → focused Termux:X11 Activity → Fedora/Wayland surface.

INPUT_SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$INPUT_SCRIPT_DIR/../scripts/lib/common.sh"

fedora_require_termux
fedora_require_non_root

COMMAND=status
READ_PREFERENCES=0
while (( $# > 0 )); do
  case "$1" in
    status) COMMAND=status; shift ;;
    guide|guidance) COMMAND=guide; shift ;;
    --read-preferences) READ_PREFERENCES=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: input/keyboard-mode.sh [status|guide] [--read-preferences]

Read-only Linux keyboard focus status and user guidance.
It never changes Android settings or Termux:X11 preferences.
EOF
      exit 0
      ;;
    *)
      printf '[fedora-shell][error] Unknown keyboard-mode option: %s\n' "$1" >&2
      exit 64
      ;;
  esac
done

x11_socket="$FEDORA_TERMUX_PREFIX/tmp/.X11-unix/X${FEDORA_DISPLAY#:}"
runtime_dir="$FEDORA_TERMUX_PREFIX/tmp/fedora-runtime"
state_file="$FEDORA_STATE_RECORD_DIR/linux-mode-state.env"
session_state="$runtime_dir/fedora-session-state.env"
for keyboard_path in "$x11_socket" "$runtime_dir" "$state_file" "$session_state"; do
  fedora_path_is_safe "$keyboard_path" || {
    printf '[fedora-shell][error] Refusing an unsafe keyboard status path: %s\n' \
      "$keyboard_path" >&2
    exit 1
  }
done

keyboard_state() {
  if fedora_keyboard_mode_valid "$FEDORA_KEYBOARD_MODE"; then
    printf '%s\n' "$FEDORA_KEYBOARD_MODE"
  else
    printf 'invalid:%s\n' "$FEDORA_KEYBOARD_MODE"
  fi
}

read_state_value() {
  local key="$1"
  if [[ -f "$state_file" && ! -L "$state_file" ]]; then
    sed -n "s/^${key}=//p" "$state_file" | sed -n '1p'
  fi
}

wayland_display_from_state() {
  local display=""
  if [[ -f "$session_state" && ! -L "$session_state" ]]; then
    display="$(sed -n 's/^WAYLAND_DISPLAY=//p' "$session_state" | sed -n '1p' || true)"
  fi
  if [[ "$display" =~ ^wayland-[0-9]+$ \
    && -S "$runtime_dir/$display" && ! -L "$runtime_dir/$display" ]]; then
    printf '%s\n' "$display"
  else
    printf '%s\n' unavailable
  fi
}

print_status() {
  local x11_state=absent wayland_display mode phase
  [[ -S "$x11_socket" && ! -L "$x11_socket" ]] && x11_state=ready
  wayland_display="$(wayland_display_from_state)"
  mode="$(read_state_value mode || true)"
  phase="$(read_state_value phase || true)"

  printf 'fedora-shell-keyboard-mode-v1\n'
  printf 'keyboard_mode=%s\n' "$(keyboard_state)"
  printf 'linux_mode_state=%s/%s\n' "${mode:-unknown}" "${phase:-unknown}"
  printf 'termux_x11_socket=%s\n' "$x11_state"
  printf 'wayland_display=%s\n' "$wayland_display"
  printf '%s\n' 'focus_path=Android focused Activity -> Termux:X11 -> Wayland/Mutter -> GNOME'
  printf '%s\n' 'android_global_keys=SystemUI-owned; no global interception is attempted'
  printf '%s\n' 'android_mutation=none'

  if (( READ_PREFERENCES )); then
    printf '\n[Termux:X11 preferences; read-only]\n'
    if fedora_have_cmd termux-x11-preference; then
      termux-x11-preference list 2>&1 || true
    else
      printf '%s\n' 'termux-x11-preference=unavailable'
    fi
  fi
}

print_guide() {
  cat <<'EOF'
Linux Mode keyboard focus (только когда Fedora видима)

1. Откройте и оставьте на переднем плане Activity Termux:X11.
2. Нажмите на поверхность Fedora, чтобы именно она получила фокус.
3. Обычные клавиши и сочетания Ctrl/Alt/Super/F-клавиш проходят в Fedora
   через сфокусированную Activity; проверяйте их, например, в терминале GNOME.
4. Для нижнего свайпа Home/Overview и Back оставьте в Termux:X11 параметр
   «Fullscreen on device display» выключенным.

Android сохраняет защищённые глобальные клавиши и панели: Home, Back,
громкость, шторка уведомлений, скриншоты, DeX/системные сочетания и иные
обработчики SystemUI могут остаться у Android. Обычное приложение не может
переназначить их на Fedora через публичный SDK. Эта схема не использует
overlay, AccessibilityService, IME, root, AppOps или изменение Android.

Если сочетание уходит в Android, вернитесь в Termux:X11, тапните по Fedora
поверхности и повторите. Для read-only проверки используйте:
  input/keyboard-mode.sh status --read-preferences
EOF
}

case "$COMMAND" in
  status) print_status ;;
  guide) print_guide ;;
esac
