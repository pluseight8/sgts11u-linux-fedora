# Version policy and provenance

Срез: **2026-08-31**. Версии здесь фиксируют исследованный baseline, а не
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
| virglrenderer | probe only; no vendored commit yet | [Termux issue context](https://github.com/termux/termux-packages/issues/19529) |
| ANGLE | research candidate only | [ANGLE source](https://chromium.googlesource.com/angle/angle/) |
| Android API | actual `ro.build.version.sdk` required | [Android Surface API](https://developer.android.com/reference/android/view/Surface) |
| Android controller build | AGP 8.8.2, compile/target SDK 35, min SDK 26 | `android/` prototype; update only with a tested Android toolchain |

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
