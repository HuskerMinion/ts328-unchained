#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the stage-1 initrd (initrd.boot) for the TS-328.
# Needs: curl, dpkg-deb, cpio, gzip, sha256sum. Output: ./out/initrd.boot
#
# busybox comes from Debian's busybox-static package, pinned by its SHA-256.
# It is fetched from the Debian mirror, or from snapshot.debian.org once the
# mirror has dropped this version. Source:
# https://snapshot.debian.org/package/busybox/1.35.0-4%2Bdeb12u1/
set -eu
cd "$(dirname "$0")"
DEB=busybox-static_1.35.0-4+deb12u1+b1_arm64.deb
SHA256=732c9135564fc71337e0e05fb4da4d11e6c28c1834bce3e405e575afef2a52f5
SHA1=87bf504541e6583e6fef6ec0bc67537f53c327f2
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
curl -fsSL -o "$W/$DEB" "https://deb.debian.org/debian/pool/main/b/busybox/$DEB" ||
	curl -fsSL -o "$W/$DEB" "https://snapshot.debian.org/file/$SHA1"
echo "$SHA256  $W/$DEB" | sha256sum -c --quiet - || { echo "busybox checksum mismatch" >&2; exit 1; }
dpkg-deb -x "$W/$DEB" "$W/bb"
R="$W/root"; mkdir -p "$R/bin" "$R/sbin" "$R/proc" "$R/sys" "$R/dev" "$R/tmp" "$R/newroot"
cp "$W/bb/bin/busybox" "$R/bin/busybox"
install -m 755 init "$R/init"; ln -s init "$R/linuxrc"
mkdir -p out; (cd "$R" && find . | LC_ALL=C sort | cpio -o -H newc --owner=0:0 2>/dev/null | gzip -9 -n) > out/initrd.boot
ls -l out/initrd.boot
