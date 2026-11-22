// SPDX-License-Identifier: GPL-2.0-only
/*
 * emmc-boot1-test: write/verify/restore test on the eMMC boot1 partition
 * through MMC_IOC_CMD (the block device stays read-only).
 *
 * Development tool for the eMMC driver; not needed for installation.
 * It WRITES to the eMMC hardware boot area boot1 (and restores it to
 * zeros). Do not run it unless boot1 is unused on your unit.
 *
 * Needs dw_mmc_rtd129x.boot1_writes=1 (sysfs, 0644). The driver then lets
 * CMD24 through only while boot1 is the selected hardware partition; the
 * MMC block driver selects it for ioctls on /dev/mmcblk0boot1.
 *
 * Steps: read N blocks and require all zeros (boot1 is unused on the
 * TS-328), write a pattern, read back and compare, write zeros, read back
 * and require zeros. Single-block CMD24/CMD17 only.
 *
 * Build: aarch64-linux-gnu-gcc -static -O2 -o emmc-boot1-test emmc-boot1-test.c
 * Usage: emmc-boot1-test [/dev/mmcblk0boot1] [blocks, default 128]
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <linux/mmc/ioctl.h>

#define BLK		512
#define MMC_RSP_PRESENT	(1 << 0)
#define MMC_RSP_CRC	(1 << 2)
#define MMC_RSP_OPCODE	(1 << 4)
#define MMC_RSP_R1	(MMC_RSP_PRESENT | MMC_RSP_CRC | MMC_RSP_OPCODE)
#define MMC_CMD_ADTC	(1 << 5)

static int xfer(int fd, int write, unsigned int blk, unsigned char *buf)
{
	struct mmc_ioc_cmd ic;

	memset(&ic, 0, sizeof(ic));
	ic.opcode = write ? 24 : 17;
	ic.arg = blk;			/* block addressed (> 2 GiB card) */
	ic.flags = MMC_RSP_R1 | MMC_CMD_ADTC;
	ic.write_flag = write;
	ic.blksz = BLK;
	ic.blocks = 1;
	ic.data_timeout_ns = 1000000000;
	mmc_ioc_cmd_set_data(ic, buf);

	if (ioctl(fd, MMC_IOC_CMD, &ic) < 0) {
		fprintf(stderr, "%s block %u: %s\n", write ? "CMD24" : "CMD17",
			blk, strerror(errno));
		return -1;
	}
	if (ic.response[0] & 0xfff80000) {
		fprintf(stderr, "%s block %u: R1 %#x\n", write ? "CMD24" : "CMD17",
			blk, ic.response[0]);
		return -1;
	}
	return 0;
}

static void pattern(unsigned char *buf, unsigned int blk)
{
	unsigned int i;

	for (i = 0; i < BLK; i++)
		buf[i] = (unsigned char)(blk * 31 + i * 7 + 0x5a);
}

static int check(int fd, unsigned int n, int zeros, const char *what)
{
	unsigned char buf[BLK], want[BLK];
	unsigned int b;

	for (b = 0; b < n; b++) {
		if (xfer(fd, 0, b, buf))
			return -1;
		if (zeros)
			memset(want, 0, BLK);
		else
			pattern(want, b);
		if (memcmp(buf, want, BLK)) {
			fprintf(stderr, "%s: block %u differs\n", what, b);
			return -1;
		}
	}
	printf("%s: %u blocks OK\n", what, n);
	return 0;
}

static int fill(int fd, unsigned int n, int zeros, const char *what)
{
	unsigned char buf[BLK];
	unsigned int b;

	for (b = 0; b < n; b++) {
		if (zeros)
			memset(buf, 0, BLK);
		else
			pattern(buf, b);
		if (xfer(fd, 1, b, buf))
			return -1;
	}
	printf("%s: %u blocks written\n", what, n);
	return 0;
}

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "/dev/mmcblk0boot1";
	unsigned int n = argc > 2 ? strtoul(argv[2], NULL, 0) : 128;
	int fd, ret = 1;

	if (!strstr(dev, "boot1")) {
		fprintf(stderr, "refusing: %s is not a boot1 device\n", dev);
		return 2;
	}
	if (!n || n > 4096) {
		fprintf(stderr, "blocks must be 1..4096\n");
		return 2;
	}

	fd = open(dev, O_RDONLY);
	if (fd < 0) {
		perror(dev);
		return 2;
	}

	if (check(fd, n, 1, "1 initial zeros"))
		goto out;		/* not zeros: do not touch it */
	if (fill(fd, n, 0, "2 pattern write"))
		goto restore;
	if (check(fd, n, 0, "3 pattern readback"))
		goto restore;
	ret = 0;
restore:
	if (fill(fd, n, 1, "4 restore zeros") || check(fd, n, 1, "5 zeros readback"))
		ret = 1;
out:
	close(fd);
	printf("%s\n", ret ? "FAIL" : "PASS");
	return ret;
}
