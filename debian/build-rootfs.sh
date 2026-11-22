#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the Debian 12 (bookworm) arm64 root file system for the TS-328, rootless.
# Needs: mmdebstrap, debian-archive-keyring, qemu-user-static (binfmt),
#        e2fsprogs >= 1.47.1 built with libarchive (for mke2fs -d <tarball>).
#
# Usage:
#   AUTHORIZED_KEYS=~/.ssh/id_ed25519.pub [ADMIN_USER=name] [TZ_NAME=Area/City] ./build-rootfs.sh
# Output: out/rootfs.tar, out/root.ext4
#
# AUTHORIZED_KEYS  your SSH public key(s); they are built into the image, so
#                  do not share the image.
# ADMIN_USER       optional: create this user with the key and passwordless
#                  sudo, and refuse root logins over SSH (05-no-root.conf:
#                  sshd uses the first value it reads, so it must sort first).
# TZ_NAME          time zone, default Etc/UTC.
set -eu
cd "$(dirname "$0")"; mkdir -p out
KEYS=${AUTHORIZED_KEYS:?set AUTHORIZED_KEYS to your SSH public key file}
TZ_NAME=${TZ_NAME:-Etc/UTC}
ADMIN_USER=${ADMIN_USER:-}

# Inputs
[ -f "$KEYS" ] || { echo "AUTHORIZED_KEYS: no such file: $KEYS" >&2; exit 1; }
if grep -q "PRIVATE KEY" "$KEYS"; then echo "AUTHORIZED_KEYS is a private key; use the .pub file" >&2; exit 1; fi
ssh-keygen -l -f "$KEYS" >/dev/null || { echo "AUTHORIZED_KEYS: not an SSH public key file" >&2; exit 1; }
echo "$TZ_NAME" | grep -Eq '^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$' || { echo "TZ_NAME: invalid" >&2; exit 1; }
[ -z "$ADMIN_USER" ] || echo "$ADMIN_USER" | grep -Eq '^[a-z][a-z0-9_-]{0,30}$' || { echo "ADMIN_USER: invalid" >&2; exit 1; }
v=$(mke2fs -V 2>&1 | sed -n 's/^mke2fs \([0-9.]*\).*/\1/p')
printf '1.47.1\n%s\n' "$v" | sort -V -C || { echo "mke2fs $v is too old: need 1.47.1 or later" >&2; exit 1; }

if [ -n "$ADMIN_USER" ]; then
	ADMIN_HOOK="chroot \"\$1\" sh -c 'useradd -m -s /bin/bash -G sudo $ADMIN_USER &&
		install -d -m 700 -o $ADMIN_USER -g $ADMIN_USER /home/$ADMIN_USER/.ssh &&
		install -m 600 -o $ADMIN_USER -g $ADMIN_USER /root/.ssh/authorized_keys /home/$ADMIN_USER/.ssh/authorized_keys &&
		echo \"$ADMIN_USER ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/10-admin && chmod 440 /etc/sudoers.d/10-admin &&
		printf \"PermitRootLogin no\\\\n\" > /etc/ssh/sshd_config.d/05-no-root.conf'"
else
	ADMIN_HOOK=true
fi

# sync-in copies the overlay with the builder's owner and modes, also onto
# existing directories such as / and /etc: give every overlay path back to
# root, with no group or other write access.
OVL_PATHS=$(cd overlay && find . | sed 's|^\./|/|; s|^\.$|/|' | LC_ALL=C sort | tr '\n' ' ')
OVERLAY_FIX="for p in $OVL_PATHS; do chown -h 0:0 \"\$1\$p\" && if [ -d \"\$1\$p\" ]; then chmod 755 \"\$1\$p\"; else chmod go-w \"\$1\$p\"; fi || exit 1; done"

mmdebstrap --mode=unshare --arch=arm64 --variant=important \
  --keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
  --include=systemd-sysv,udev,systemd-resolved,openssh-server,sudo,mdadm,smartmontools,kmod,e2fsprogs,iproute2,iputils-ping,ca-certificates,nano,less,curl,unattended-upgrades,python3-gi,systemd-timesyncd,bash-completion,alsa-utils,locales,apparmor \
  --components=main --aptopt='APT::Install-Recommends "false"' \
  --customize-hook='sync-in overlay /' \
  --customize-hook="$OVERLAY_FIX" \
  --customize-hook="upload \"$KEYS\" /root/.ssh/authorized_keys" \
  --customize-hook='chroot "$1" sh -c "chmod 700 /root /root/.ssh; chmod 600 /root/.ssh/authorized_keys; chown -R root:root /root"' \
  --customize-hook="$ADMIN_HOOK" \
  --customize-hook='chroot "$1" systemctl enable systemd-networkd systemd-resolved systemd-timesyncd ssh' \
  --customize-hook='ln -sf /run/systemd/resolve/stub-resolv.conf "$1/etc/resolv.conf"' \
  --customize-hook="test -e \"\$1/usr/share/zoneinfo/$TZ_NAME\" && ln -sf /usr/share/zoneinfo/$TZ_NAME \"\$1/etc/localtime\"" \
  --customize-hook='ln -sf /dev/null "$1/etc/systemd/system/fstrim.timer"' \
  --customize-hook='rm -f "$1"/etc/ssh/ssh_host_*' \
  bookworm out/rootfs.tar \
  "deb http://deb.debian.org/debian bookworm main" \
  "deb http://deb.debian.org/debian bookworm-updates main" \
  "deb http://security.debian.org/debian-security bookworm-security main"
# nothing in the image may belong to the user who built it (home folders
# aside: an ADMIN_USER can get the same uid)
me=$(id -u)
if [ "$me" != 0 ]; then
	tar --numeric-owner -tvf out/rootfs.tar | awk -v u="$me" '{split($2, o, "/")} o[1] == u && $6 !~ /^\.\/home\// {print; n++} END {exit n > 0}' ||
		{ echo "rootfs.tar has files owned by uid $me (listed above)" >&2; exit 1; }
fi
# ext4 without features that the vendor 4.2.8 kernel (QTS) cannot mount, so
# QTS can still read it
rm -f out/root.ext4
mke2fs -q -F -t ext4 -O ^metadata_csum_seed,^orphan_file -L DEBROOT -d out/rootfs.tar out/root.ext4 3G
ls -l out/
