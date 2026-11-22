#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# mkboot.sh <build-dir> <initrd-dir> <out-dir>
# Produces U-Boot-ready boot files for the QNAP TS-328 vendor U-Boot:
#  - Image with text_offset patched to 0x200000 (vendor booti places the
#    kernel at DRAM base + text_offset and ignores the "anywhere" flag)
#  - realtek.dtb, initrd.boot (gz cpio), *.cksum (POSIX cksum format)
set -e
B=$1; I=$2; O=$3; mkdir -p "$O"
python3 -I - "$B/arch/arm64/boot/Image" "$O/Image" <<'PY'
import struct,sys
d=bytearray(open(sys.argv[1],'rb').read())
assert d[56:60]==b'ARMd', 'not an arm64 Image'
size=struct.unpack_from('<Q',d,16)[0]
struct.pack_into('<Q',d,8,0x200000)
end=0x200000+size
assert end < 0x1b00000, 'kernel footprint %#x overlaps audio fw at 0x1b00000'%end
open(sys.argv[2],'wb').write(d)
print('Image: text_offset=0x200000 image_size=%#x ends at %#x'%(size,end))
PY
cp "$B/arch/arm64/boot/dts/realtek/rtd1296-qnap-ts328.dtb" "$O/realtek.dtb"
(cd "$I" && find . | cpio -o -H newc --owner=0:0 2>/dev/null | gzip -9) > "$O/initrd.boot"
cd "$O"; for f in Image realtek.dtb initrd.boot; do set -- $(cksum < $f); echo "$1 $2 /ts328/build/$f" > $f.cksum; done
ls -l "$O"
