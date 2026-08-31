# Fedora Shell session environment. This file is sourced by Fedora login
# shells; it does not force an X11-only desktop.

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-GNOME}"
  export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-gnome}"
  export GDK_BACKEND="${GDK_BACKEND:-wayland,x11}"
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"
  export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland,x11}"
  export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-1}"
  export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"
fi

