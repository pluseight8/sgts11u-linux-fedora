# Fedora ARM64 rootfs

The installer uses the official Fedora OCI image `fedora:44` and asks
PRoot-Distro for `aarch64`/`linux/arm64`. It does not download a rootfs from a
forum, Telegram channel, or an unreviewed mirror.

PRoot-Distro resolves the OCI manifest for the requested architecture and
verifies every layer digest while downloading. The resolved manifest is stored
in its local container metadata. Because `fedora:44` is a mutable registry tag,
the installer records the local manifest/image metadata and package inventory;
it intentionally does not invent a digest in this repository.

If the official image cannot be pulled, stop and capture the error. Do not
replace it with an arbitrary rootfs. A future reproducible builder may use
Fedora's official repositories and publish a reviewed OCI archive, but that is
not needed while the official ARM64 image is available.

