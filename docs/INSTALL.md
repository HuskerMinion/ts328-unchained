# Installing ts328-unchained

This installs Debian with the 6.18 kernel on the TS-328's internal eMMC and
makes it the default boot. U-Boot (in SPI flash) is never touched, so the
USB Copy recovery boot always stays available.

Read the whole guide first. You need about two hours, most of it waiting.

## 0. What you need

- A Linux PC (Debian 13, Ubuntu 25.04 or newer; see the e2fsprogs note) with:
  ```sh
  sudo apt install git make gcc-aarch64-linux-gnu bison flex bc libssl-dev libelf-dev \
    python3 cpio gzip curl dpkg-dev mmdebstrap debian-archive-keyring \
    qemu-user-static binfmt-support e2fsprogs fdisk
  ```
  `debian/build-rootfs.sh` needs **e2fsprogs 1.47.1 or later** (`mke2fs -V`);
  Debian 12 and Ubuntu 24.04 ship 1.47.0.
- Two USB sticks: one for the backup (any size, or use a share), and one of
  **8 GB or more** that becomes the boot and rescue stick (it is wiped).
- An SSH key pair on the PC (`ssh-keygen -t ed25519` if you have none).
- Optional: a 3.3 V USB serial adapter on header J1 (pin 1 = board TX,
  pin 4 = GND, 115200 8N1). Output only: the board takes no serial input.

**Remove the drive trays** for the test boot and the installation. The
QTS data volumes (md + LVM) cannot be used from this system, so copy your
data off first if you want to keep it.

## 1. Back up everything (from QTS)

Enable SSH in QTS (Control Panel > Network & File Services > Telnet / SSH)
and log in as an administrator. Plug in the **backup** stick (not the boot
stick) and change to it, for example `cd /share/external/DEV3301_1`.

```sh
dd if=/dev/mmcblk0      of=emmc-user.img  bs=1M
dd if=/dev/mmcblk0boot0 of=emmc-boot0.img bs=1M
dd if=/dev/mmcblk0boot1 of=emmc-boot1.img bs=1M
cat /dev/mtd0 > spi-nor.img
sha256sum *.img > SHA256SUMS
```

Copy the images to your PC and keep them safe. They are the only way back
to QTS, and they contain the board's serial numbers and MAC addresses, so
never publish them.

## 2. Build (on the PC)

```sh
git clone <this repository> ts328-unchained && cd ts328-unchained
stage1/build.sh                                   # -> stage1/out/initrd.boot
kernel/build.sh                                   # -> kernel/out/{Image,realtek.dtb,initrd.boot}{,.cksum}
AUTHORIZED_KEYS=~/.ssh/id_ed25519.pub debian/build-rootfs.sh   # -> debian/out/root.ext4
```

`debian/build-rootfs.sh` also takes `ADMIN_USER=<name>` (an admin user with
your key and sudo; root logins over SSH are then refused) and
`TZ_NAME=<Area/City>` (default `Etc/UTC`). The image contains your
`authorized_keys`: do not share it.

The audio CPU firmware `bluecore.audio` is Realtek's and is not distributed
here. Take it, with its `.cksum` file, from partition 2 of your backup:

```sh
dev=$(sudo losetup -P -r -f --show emmc-user.img)
sudo mount -o ro ${dev}p2 /mnt
cp /mnt/boot/bluecore.audio /mnt/boot/bluecore.audio.cksum kernel/out/
sudo umount /mnt; sudo losetup -d $dev
```

## 3. Make the boot stick and test it (nothing on the eMMC changes)

Find the stick with `lsblk` and double-check the device name: everything
on it is erased. Here it is `/dev/sdX`.

```sh
sudo wipefs -a /dev/sdX
sudo sfdisk /dev/sdX <<'EOF'
label: dos
start=2048, size=16MiB, type=83
size=256MiB, type=83
type=83
EOF
sudo mkfs.ext2 -q -L TS328BOOT /dev/sdX2
sudo mount /dev/sdX2 /mnt && sudo mkdir /mnt/boot
sudo cp kernel/out/Image* kernel/out/realtek.dtb* kernel/out/initrd.boot* kernel/out/bluecore.audio* /mnt/boot/
sudo umount /mnt
sudo dd if=debian/out/root.ext4 of=/dev/sdX3 bs=4M conv=fsync status=progress
sudo e2fsck -fp /dev/sdX3 && sudo resize2fs /dev/sdX3
```

Partition 1 stays empty; U-Boot reads partition 2. Only ever use the
`initrd.boot` built here on the stick: with QTS's own initrd (or a QNAP
recovery image), holding USB Copy makes QTS clone the whole stick onto
the eMMC.

Boot it:

1. Power off. Insert the stick in a **rear** USB port (verified; the front
   port is untested).
2. Hold the front **USB Copy** button and power on. Keep holding until the
   box beeps, then let go.
3. U-Boot loads the kernel from the stick, and stage 1 prefers the root on
   the stick on this kind of boot. After about a minute the box says
   "Boot complete".
4. Find its address in your router's DHCP leases (host name `ts328`) and log
   in: `ssh root@<address>` (or `ssh <ADMIN_USER>@<address>`). There is no
   password; only your key works.

Check that everything works: `lsblk`, `ip addr`, `dmesg`. This stick is
also your **rescue stick**: keep it.

## 4. Install to the eMMC (from the system running on the stick)

All steps run on the NAS, as root, in the stick system. Nothing on the eMMC
may be mounted.

The eMMC driver protects everything below sector 1009664 (partitions 1 to 6,
QTS) with `write_min_lba`. Lift it only for the steps that need it; a
reboot restores it.

### 4.1 Create partition 7

Save the current table first and copy it off the box:

```sh
sfdisk -d /dev/mmcblk0 > /root/mmcblk0-pt-before.txt
cat /sys/class/block/mmcblk0p6/start /sys/class/block/mmcblk0p6/size   # expect 990240 and 17376
```

Stop if the numbers differ: your layout is not the one this guide was
tested on. Otherwise:

```sh
echo 0 > /sys/module/dw_mmc_rtd129x/parameters/write_min_lba
echo ',+' | sfdisk -N 4 /dev/mmcblk0                          # grow the extended partition
echo 'start=1009664, type=83' | sfdisk --append /dev/mmcblk0  # new logical partition 7
echo 1009664 > /sys/module/dw_mmc_rtd129x/parameters/write_min_lba
partx -u /dev/mmcblk0
cat /sys/class/block/mmcblk0p7/start                          # must print 1009664
```

### 4.2 Write the Debian root to partition 7

From the PC (3 GiB at about 7 MB/s, so about 8 minutes):

```sh
ssh root@<address> 'dd of=/dev/mmcblk0p7 bs=4M conv=fsync' < debian/out/root.ext4
```

Then on the NAS:

```sh
e2fsck -fp /dev/mmcblk0p7 && resize2fs /dev/mmcblk0p7
tune2fs -U random -L DEBROOT-EMMC /dev/mmcblk0p7   # tell it apart from the stick copy
```

### 4.3 Put the boot files on partition 2

The QTS kernel files are renamed, not deleted, so QTS can be brought back.

```sh
echo 0 > /sys/module/dw_mmc_rtd129x/parameters/write_min_lba
mount /dev/mmcblk0p2 /mnt && cd /mnt/boot
for f in Image realtek.dtb initrd.boot; do mv $f $f.qts; mv $f.cksum $f.cksum.qts; done
mkdir -p /tmp/s && mount -o ro /dev/sda2 /tmp/s      # the stick's boot partition (check with lsblk)
cp /tmp/s/boot/Image* /tmp/s/boot/realtek.dtb* /tmp/s/boot/initrd.boot* .
umount /tmp/s; cd /; sync; umount /mnt
echo 1009664 > /sys/module/dw_mmc_rtd129x/parameters/write_min_lba
```

Leave `bluecore.audio` and QTS's other files on partition 2 alone.

### 4.4 First boot from the eMMC

Power off, remove the stick, power on (no button). The box boots Debian
from eMMC partition 7 and says "Boot complete". Log in as before.

## 5. Platform extras

Front panel, fan control, RAID and voice prompts. From the PC:

```sh
scp -r platform root@<address>:/root/
```

On the NAS:

```sh
install -m 755 /root/platform/sbin/* /usr/local/sbin/
install -m 644 /root/platform/systemd/*.service /etc/systemd/system/
install -D -m 755 /root/platform/system-shutdown/qnap-mcu-poweroff /usr/lib/systemd/system-shutdown/qnap-mcu-poweroff
systemctl daemon-reload && systemctl enable --now qnap-fan.service qnap-panel.service
sh /root/platform/voice/install.sh
```

The logind settings for the power button are already in the image.

For the RAID voice prompts, add `PROGRAM /usr/local/sbin/md-event` to
`/etc/mdadm/mdadm.conf` and run `systemctl restart mdmonitor`.

## 6. Recovery and going back

- **The eMMC system does not boot:** boot the rescue stick with USB Copy
  held (step 3) and repair the eMMC from there.
- **Back to the QTS kernel:** from the rescue stick system, lift
  `write_min_lba` (`echo 0 > ...`), mount partition 2, and rename the
  `*.qts` files back over `Image`, `realtek.dtb`, `initrd.boot` and their
  `.cksum` files. QTS ignores partition 7.
- **Full restore:** from the rescue stick system, never from the eMMC root:
  ```sh
  echo 0 > /sys/module/dw_mmc_rtd129x/parameters/write_min_lba
  dd if=emmc-user.img of=/dev/mmcblk0 bs=4M conv=fsync
  ```

## 7. Optional: remove QTS from the eMMC

Once you no longer need QTS, its files can go (about 450 MB). Your backup
images from step 1 are then the only way back. U-Boot only reads `Image`,
`realtek.dtb`, `initrd.boot`, `bluecore.audio` and their `.cksum` files.

```sh
echo 0 > /sys/module/dw_mmc_rtd129x/parameters/write_min_lba
mount /dev/mmcblk0p2 /mnt && cd /mnt/boot
rm -f rootfs2.bz* rootfs_ext.tgz* qpkg.tar* *.sign *.qts
cd /; sync; umount /mnt
# partition 3 holds QTS's second copy; replace it with a spare copy of the boot set
mount /dev/mmcblk0p3 /mnt && rm -rf /mnt/boot && mkdir /mnt/boot
mkdir -p /tmp/s && mount -o ro /dev/mmcblk0p2 /tmp/s && cp /tmp/s/boot/* /mnt/boot/ && umount /tmp/s
sync; umount /mnt
echo 1009664 > /sys/module/dw_mmc_rtd129x/parameters/write_min_lba
```

Do not delete partitions 1 to 6 themselves, and never write to the SPI
flash (`/dev/mtd*` does not exist under this kernel) or the eMMC boot
areas (`mmcblk0boot0`, `mmcblk0boot1`).
