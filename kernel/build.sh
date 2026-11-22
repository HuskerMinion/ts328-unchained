#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Build the TS-328 kernel: Linux 6.18.64 + kernel/patches, configs merged.
# Needs: git, gcc-aarch64-linux-gnu, make, bison, flex, bc, libssl-dev,
#        libelf-dev, python3, cpio, gzip.
# Usage: ./build.sh [stage1-initrd]
#   stage1-initrd defaults to ../stage1/out/initrd.boot (run stage1/build.sh first)
# Output: out/{Image,realtek.dtb,initrd.boot} and their U-Boot .cksum files
set -eu
cd "$(dirname "$0")"; top=$(pwd)
V=v6.18.64
BASE=fd7cfd39c88596fec816639ad83cbf3e9d316372	# the commit v6.18.64 points to
INITRD=${1:-$top/../stage1/out/initrd.boot}
[ -f "$INITRD" ] || { echo "missing $INITRD: run stage1/build.sh first" >&2; exit 1; }

[ -d linux ] || git -c advice.detachedHead=false clone -q --depth 1 --branch $V \
	https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux
cd linux
git cat-file -e "$BASE^{commit}" 2>/dev/null || { echo "linux/ does not contain $V ($BASE)" >&2; exit 1; }

# (Re)apply the patches whenever the series changes.
stamp=$(cat "$top"/patches/*.patch | sha256sum | cut -d' ' -f1)
if [ "$(cat .ts328-series 2>/dev/null)" != "$stamp" ]; then
	git am --abort >/dev/null 2>&1 || true
	git reset -q --hard "$BASE"
	git clean -qfdx
	git -c user.name=build -c user.email=build@localhost am -q "$top"/patches/*.patch
	echo "$stamp" > .ts328-series
fi

# keep the build user, host and time zone out of the kernel version string
export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=ts328-unchained TZ=UTC
B=$top/build; A="ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
make -s $A O=$B allnoconfig
FRAGS="phase1 irqmux pcie usb gmac platform emmc debian audio sata containers cpufreq production hardening"
scripts/kconfig/merge_config.sh -m -O $B $B/.config $(for f in $FRAGS; do echo "$top/configs/ts328-$f.config"; done) >/dev/null
make -s $A O=$B olddefconfig
make -s -j"$(nproc)" $A O=$B Image dtbs

mkdir -p $top/out
# Vendor U-Boot limits:
# - booti places the kernel at DRAM base + text_offset: use 2 MiB, and keep
#   the footprint below the audio firmware at 0x1b00000
# - it decompresses at most 20 MiB of a gzip Image
python3 - "$B/arch/arm64/boot/Image" "$top/out/Image" <<'PY'
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
assert d[56:60] == b'ARMd', 'not an arm64 Image'
struct.pack_into('<Q', d, 8, 0x200000)
assert 0x200000 + struct.unpack_from('<Q', d, 16)[0] < 0x1b00000, 'Image overlaps the audio firmware'
assert len(d) <= 20 * 1024 * 1024, 'Image too big for U-Boot gunzip (20 MiB)'
open(sys.argv[2], 'wb').write(d)
PY
gzip -9 -n -f -c $top/out/Image > $top/out/Image.gz && mv $top/out/Image.gz $top/out/Image
cp $B/arch/arm64/boot/dts/realtek/rtd1296-qnap-ts328.dtb $top/out/realtek.dtb
cp "$INITRD" $top/out/initrd.boot
cd $top/out && for f in Image realtek.dtb initrd.boot; do set -- $(cksum < $f); echo "$1 $2 /ts328/build/$f" > $f.cksum; done
ls -l $top/out
