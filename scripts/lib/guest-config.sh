#!/data/data/com.termux/files/usr/bin/bash

# Guest-side installation helpers. Source after scripts/lib/common.sh.

fedora_sync_guest_config() {
  local install_root
  install_root="$(fedora_install_root)"
  [[ -d "$install_root" ]] || { fedora_die "Installed project tree is missing: $install_root"; return 1; }

  fedora_pd_login_root /usr/bin/install -d -m 0755 \
    /etc/profile.d \
    /etc/dconf/db/fedora-shell.d \
    /usr/local/bin || return 1

  fedora_pd_copy_to "$install_root/fedora/gnome/fedora-session" /usr/local/bin/fedora-session || return 1
  fedora_pd_copy_to "$install_root/fedora/gnome/fedora-run" /usr/local/bin/fedora-run || return 1
  fedora_pd_copy_to "$install_root/fedora/config/gnome-environment.sh" /etc/profile.d/fedora-shell-environment.sh || return 1
  fedora_pd_copy_to "$install_root/fedora/config/dconf.ini" /etc/dconf/db/fedora-shell.d/00-fedorashell || return 1
  fedora_pd_copy_to "$install_root/gpu/scripts/check-renderer.sh" /usr/local/bin/fedora-gpu-check || return 1
  fedora_pd_copy_to "$install_root/gpu/scripts/measure-frame-pacing-guest.sh" /usr/local/bin/fedora-frame-pacing || return 1

  fedora_pd_login_root /bin/chmod 0755 \
    /usr/local/bin/fedora-session \
    /usr/local/bin/fedora-run \
    /usr/local/bin/fedora-gpu-check \
    /usr/local/bin/fedora-frame-pacing || return 1

  fedora_pd_login_root /bin/bash "$FEDORA_GUEST_PROJECT_ROOT/fedora/gnome/install-integration.sh" || return 1
  fedora_pd_login_root /bin/bash -c 'command -v dconf >/dev/null 2>&1 && dconf update || true'
}

fedora_run_guest_setup() {
  local install_root
  install_root="$(fedora_install_root)"
  [[ -d "$install_root" ]] || { fedora_die "Installed project tree is missing: $install_root"; return 1; }
  fedora_pd_login_root /usr/bin/env \
    "FEDORA_RELEASE=$FEDORA_RELEASE" \
    "FEDORA_USER=$FEDORA_USER" \
    /bin/bash "$FEDORA_GUEST_PROJECT_ROOT/fedora/rootfs/install-gnome.sh"
}
