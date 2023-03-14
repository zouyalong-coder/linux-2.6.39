/* -*- linux-c -*- ------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author H. Peter Anvin
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

/*
 * Get EDD BIOS disk information
 */

#include "boot.h"
#include <linux/edd.h>

#if defined(CONFIG_EDD) || defined(CONFIG_EDD_MODULE)

/*
 * Read the MBR (first sector) from a specific device.
 */
static int read_mbr(u8 devno, void *buf)
{
	struct biosregs ireg, oreg;

	initregs(&ireg);
	ireg.ax = 0x0201;		/* Legacy Read, one sector */
	ireg.cx = 0x0001;		/* Sector 0-0-1 */
	ireg.dl = devno;
	ireg.bx = (size_t)buf;

	intcall(0x13, &ireg, &oreg);

	return -(oreg.eflags & X86_EFLAGS_CF); /* 0 or -1 */
}

static u32 read_mbr_sig(u8 devno, struct edd_info *ei, u32 *mbrsig)
{
	int sector_size;
	char *mbrbuf_ptr, *mbrbuf_end;
	u32 buf_base, mbr_base;
	extern char _end[];
	u16 mbr_magic;

	sector_size = ei->params.bytes_per_sector;
	if (!sector_size)
		sector_size = 512; /* Best available guess */

	/* Produce a naturally aligned buffer on the heap */
	buf_base = (ds() << 4) + (u32)&_end;
	mbr_base = (buf_base+sector_size-1) & ~(sector_size-1);
	mbrbuf_ptr = _end + (mbr_base-buf_base);
	mbrbuf_end = mbrbuf_ptr + sector_size;

	/* Make sure we actually have space on the heap... */
	if (!(boot_params.hdr.loadflags & CAN_USE_HEAP))
		return -1;
	if (mbrbuf_end > (char *)(size_t)boot_params.hdr.heap_end_ptr)
		return -1;

	memset(mbrbuf_ptr, 0, sector_size);
	if (read_mbr(devno, mbrbuf_ptr))
		return -1;

	*mbrsig = *(u32 *)&mbrbuf_ptr[EDD_MBR_SIG_OFFSET];
	mbr_magic = *(u16 *)&mbrbuf_ptr[510];

	/* check for valid MBR magic */
	return mbr_magic == 0xAA55 ? 0 : -1;
}

static int get_edd_info(u8 devno, struct edd_info *ei)
{
	struct biosregs ireg, oreg;

	memset(ei, 0, sizeof *ei);

	/* Check Extensions Present */

	initregs(&ireg);
	ireg.ah = 0x41;
	ireg.bx = EDDMAGIC1;
	ireg.dl = devno;
	intcall(0x13, &ireg, &oreg);

	if (oreg.eflags & X86_EFLAGS_CF)
		return -1;	/* No extended information */

	if (oreg.bx != EDDMAGIC2)
		return -1;

	ei->device  = devno;
	ei->version = oreg.ah;		 /* EDD version number */
	ei->interface_support = oreg.cx; /* EDD functionality subsets */

	/* Extended Get Device Parameters */

	ei->params.length = sizeof(ei->params);
	ireg.ah = 0x48;
	ireg.si = (size_t)&ei->params;
	intcall(0x13, &ireg, &oreg);

	/* Get legacy CHS parameters */

	/* Ralf Brown recommends setting ES:DI to 0:0 */
	ireg.ah = 0x08;
	ireg.es = 0;
	intcall(0x13, &ireg, &oreg);

	if (!(oreg.eflags & X86_EFLAGS_CF)) {
		ei->legacy_max_cylinder = oreg.ch + ((oreg.cl & 0xc0) << 2);
		ei->legacy_max_head = oreg.dh;
		ei->legacy_sectors_per_track = oreg.cl & 0x3f;
	}

	return 0;
}

/**
 * @zouyalong: 从BIOS中查询 Enhanced Disk Drive 信息 
 * 代码检查内核命令行参数是否设置了edd 选项，如果edd选项设置成 off，query_edd 不做任何操作，直接返回。
 * 如果EDD被激活了，query_edd 遍历所有BIOS支持的硬盘，并获取相应硬盘的EDD信息.
 */
void query_edd(void)
{
	char eddarg[8];
	int do_mbr = 1;
#ifdef CONFIG_EDD_OFF
	int do_edd = 0;
#else
	int do_edd = 1;
#endif
	int be_quiet;
	int devno;
	struct edd_info ei, *edp;
	u32 *mbrptr;

	if (cmdline_find_option("edd", eddarg, sizeof eddarg) > 0) {
		if (!strcmp(eddarg, "skipmbr") || !strcmp(eddarg, "skip")) {
			do_edd = 1;
			do_mbr = 0;
		}
		else if (!strcmp(eddarg, "off"))
			do_edd = 0;
		else if (!strcmp(eddarg, "on"))
			do_edd = 1;
	}

	be_quiet = cmdline_find_option_bool("quiet");

	edp    = boot_params.eddbuf;
	mbrptr = boot_params.edd_mbr_sig_buffer;

	if (!do_edd)
		return;

	/* Bugs in OnBoard or AddOnCards Bios may hang the EDD probe,
	 * so give a hint if this happens.
	 */

	if (!be_quiet)
		printf("Probing EDD (edd=off to disable)... ");

	// 在代码中 0x80 是第一块硬盘，EDD_MBR_SIG_MAX 是一个宏，值为16。代码把获得的信息放入数组edd_info中。get_edd_info 方法通过调用 0x13 中断调用（设置 ah = 0x41 ) 来检查EDD是否被硬盘支持。如果EDD被支持，代码将再次调用 0x13 中断，在这次调用中 ah = 0x48，并且 si 指向一个数据缓冲区地址。中断调用之后，EDD信息将被保存到 si 指向的缓冲区地址。
	for (devno = 0x80; devno < 0x80+EDD_MBR_SIG_MAX; devno++) {
		/*
		 * Scan the BIOS-supported hard disks and query EDD
		 * information...
		 */
		if (!get_edd_info(devno, &ei)
		    && boot_params.eddbuf_entries < EDDMAXNR) {
			memcpy(edp, &ei, sizeof ei);
			edp++;
			boot_params.eddbuf_entries++;
		}

		if (do_mbr && !read_mbr_sig(devno, &ei, mbrptr++))
			boot_params.edd_mbr_sig_buf_entries = devno-0x80+1;
	}

	if (!be_quiet)
		printf("ok\n");
}

#endif
