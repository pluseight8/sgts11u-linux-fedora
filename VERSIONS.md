# Version policy and provenance

Срез: **2026-09-02**. Версии здесь фиксируют исследованный baseline, а не
гарантируют, что конкретный mirror будет отдавать тот же mutable tag.

## Selected baseline

| Component | Selected value | Provenance |
| --- | --- | --- |
| Fedora release | 44 (stable) | [Fedora release announcement](https://fedoramagazine.org/announcing-fedora-linux-44/) |
| GNOME | 50 (Fedora 44 Workstation baseline) | [Fedora Workstation 44](https://fedoramagazine.org/whats-new-fedora-workstation-44/) |
| GNOME Shell package observed | 50.4-1.fc44 (2026-08-04 package update) | [Fedora Packages](https://packages.fedoraproject.org/pkgs/gnome-shell/gnome-shell/fedora-44-updates.html) |
| Fedora image | `fedora:44` | official Docker/OCI image via PRoot-Distro |
| Fedora architecture | `aarch64` / `linux/arm64` | PRoot-Distro architecture selector |
| PRoot-Distro | v5-compatible | [upstream README/releases](https://github.com/termux/proot-distro) |
| Required Termux proot | `5.1.107-71` or newer where enforced | PRoot-Distro v5 release notes |
| Termux | minimum `v0.118.0`; exact installed version captured by diagnostics | [Termux app](https://github.com/termux/termux-app) |
| Termux:X11 | current compatible nightly; exact APK/package captured on device | [Termux:X11](https://github.com/termux/termux-x11) |
| Mesa host package | probe only; do not assume Zink/Mali support | [Termux Mesa build](https://github.com/termux/termux-packages/blob/master/packages/mesa/build.sh) |
| Android API | actual `ro.build.version.sdk` required | [Android Surface API](https://developer.android.com/reference/android/view/Surface) |
| Android controller build | AGP 8.8.2, compile/target SDK 35, min SDK 26 | `android/` prototype; update only with a tested Android toolchain |
| GNOME nested session | `gnome-shell --wayland --devkit` + official Mutter Devkit viewer | [Mutter building and running](https://github.com/GNOME/mutter/blob/main/doc/building-and-running.md) |
| Android memory policy | read-only observations; Android remains policy owner | [Android memory management](https://developer.android.com/topic/performance/memory-management) |
| Samsung RAM Plus | user-controlled OEM setting; not changed by Fedora Shell | [Samsung RAM Plus](https://www.samsung.com/sg/support/mobile-devices/what-is-ram-plus-and-how-to-use-it/) |

## Rootfs integrity

```text
FEDORA_IMAGE=fedora:44
FEDORA_ARCH=aarch64
FEDORA_MANIFEST_DIGEST=UNRECORDED_UNTIL_DEVICE_INSTALL
FEDORA_ROOTFS_TREE_SHA256=UNRECORDED_UNTIL_DEVICE_INSTALL
```

PRoot-Distro resolves the OCI manifest for the requested architecture and
verifies layer SHA-256 during download. The installer saves the local image
manifest/list output and package inventory into `$HOME/.fedora-shell/`. A
future release may replace the tag with a reviewed digest after real-device
validation; until then the project deliberately does not invent a digest.

## Device provenance

## Observed target baseline

The owner supplied console logs from a Samsung `SM-X930` running Android 16
(API 36) on an `aarch64` host. The same logs show Fedora 44, GNOME/Mutter 50.4,
PRoot-Distro 5.8.0 and `termux-x11-nightly` 1.03.01-6. This is useful release
context, not a substitute for a complete redacted diagnostics report; the
actual SoC properties, RAM, Vulkan device, panel mode and SELinux state remain
device measurements.

Run:

```bash
./scripts/diagnostics.sh --full
```

The report records:

```text
getprop
uname -a
cat /proc/cpuinfo
cat /proc/meminfo
termux-info
dumpsys display
dumpsys SurfaceFlinger
```

Do not commit reports containing personal identifiers, Wi-Fi SSIDs, serial
numbers, IMEI, or private paths. Redact before sharing.

## Reference hardware data (not a device measurement)

Samsung's public product page lists 14.6-inch 2960×1848 display and 120 Hz;
Samsung/MediaTek public material identifies the platform as Dimensity 9400+
with Arm Immortalis-G925. Regional model, firmware, RAM and available Vulkan
implementation must still come from the target tablet.
