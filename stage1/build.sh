#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the stage-1 initrd (initrd.boot) for the TS-328.
# Needs: curl, dpkg-deb, cpio, gzip, sha256sum. Output: ./out/initrd.boot
#
# busybox, mdadm, libudev1 and libc6 come from Debian packages pinned by their
# SHA-256, fetched from the Debian mirror or snapshot.debian.org. Sources:
# https://snapshot.debian.org/package/<name>/<version>/
set -eu
umask 022
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# fetch <pool path> <sha256> <sha1>: from the Debian mirror, or from
# snapshot.debian.org (by SHA-1) once the mirror has dropped the version
fetch() {
	f=$(basename "$1")
	ok() { echo "$2  $W/$f" | sha256sum -c --quiet - 2>/dev/null; }
	{ curl -fsSL -o "$W/$f" "https://deb.debian.org/debian/pool/main/$1" && ok "$@"; } ||
		{ curl -fsSL -o "$W/$f" "https://snapshot.debian.org/file/$3" && ok "$@"; } ||
		{ echo "$f: download failed or checksum mismatch" >&2; exit 1; }
	dpkg-deb -x "$W/$f" "$W/x"
}
fetch b/busybox/busybox-static_1.35.0-4+deb12u1+b1_arm64.deb \
	732c9135564fc71337e0e05fb4da4d11e6c28c1834bce3e405e575afef2a52f5 87bf504541e6583e6fef6ec0bc67537f53c327f2
# mdadm and its libraries: assembling the data RAID for the read-only root (overlay on the RAID)
fetch m/mdadm/mdadm_4.2-5_arm64.deb \
	e3285bc1dcdc816072504a3a72b9d55064937f4ed3bb2074a647a54a92ccd2ff 10d157c3d61acf4d3de8fe7355041a6dfe693379
fetch s/systemd/libudev1_252.39-1~deb12u2_arm64.deb \
	b76444b0259abfa416f8c1d9a652d208a24770667a1181aa52317b74d12a7a72 88d23334f6031c1da0b1035e802e54933dcf8c25
fetch g/glibc/libc6_2.36-9+deb12u14_arm64.deb \
	01f4330719fd4f65580e16ea5a0527f372fca750e8f588d26deaf09f2d3b1cf4 85af57bf1f9fa075163e51c99d9536154c21ab7e

R="$W/root"; mkdir -p "$R/bin" "$R/sbin" "$R/proc" "$R/sys" "$R/dev" "$R/tmp" "$R/run" "$R/etc" "$R/newroot" \
	"$R/lib/aarch64-linux-gnu"
cp "$W/x/bin/busybox" "$R/bin/busybox"
cp "$W/x/sbin/mdadm" "$R/sbin/mdadm"
for lib in libudev.so.1 libc.so.6; do
	f=$(find "$W/x" -name "$lib" | head -1); [ -n "$f" ] || { echo "$lib missing" >&2; exit 1; }
	cp -L "$f" "$R/lib/aarch64-linux-gnu/$lib"
done
f=$(find "$W/x" -name ld-linux-aarch64.so.1 | head -1); [ -n "$f" ] || { echo "ld-linux missing" >&2; exit 1; }
cp -L "$f" "$R/lib/ld-linux-aarch64.so.1"
install -m 755 init "$R/init"; ln -s init "$R/linuxrc"
mkdir -p out; (cd "$R" && find . | LC_ALL=C sort | cpio -o -H newc --owner=0:0 2>/dev/null | gzip -9 -n) > out/initrd.boot
ls -l out/initrd.boot
