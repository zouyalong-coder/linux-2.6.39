/* -*- linux-c -*- ------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

/*
 * Prepare the machine for transition to protected mode.
 */

#include "boot.h"
#include <asm/segment.h>

/*
 * Invoke the realmode switch hook if present; otherwise
 * disable all interrupts.
 * @zouyalong: 如果发现 realmode_switch hook， 那么将调用它并禁止 NMI 中断，反之将直接禁止 NMI 中断。
 * 只有当 bootloader 运行在宿主环境下（比如在 DOS 下运行 ）， hook 才会被使用。
 * 可以参考：https://www.kernel.org/doc/Documentation/x86/boot.txt
 */
static void realmode_switch_hook(void)
{
	if (boot_params.hdr.realmode_swtch) {
		asm volatile("lcallw *%0"
			     : : "m" (boot_params.hdr.realmode_swtch)
			     : "eax", "ebx", "ecx", "edx");
	} else {
		// 中断是由硬件或者软件产生的，当中断产生的时候， CPU 将得到通知。这个时候， CPU 将停止当前指令的执行，保存当前代码的环境，然后将控制权移交到中断处理程序。当中断处理程序完成之后，将恢复中断之前的运行环境，从而被中断的代码将继续运行。 NMI 中断是一类特殊的中断，往往预示着系统发生了不可恢复的错误，所以在正常运行的操作系统中，NMI 中断是不会被禁止的，但是在进入保护模式之前，由于特殊需求，代码禁止了这类中断。
		asm volatile("cli");
		outb(0x80, 0x70); /* Disable NMI */
		io_delay();
	}
}

/*
 * Disable all interrupts at the legacy PIC.
 */
// @zouyalong: 屏蔽所有中断。
static void mask_all_interrupts(void)
{
	outb(0xff, 0xa1);	/* Mask all interrupts on the secondary PIC */
	io_delay();
	outb(0xfb, 0x21);	/* Mask all but cascade on the primary PIC */
	io_delay();
}

/*
 * Reset IGNNE# if asserted in the FPU.
 */
/// @zouyalong: 复位协处理器。
static void reset_coprocessor(void)
{
	outb(0, 0xf0);
	io_delay();
	outb(0, 0xf1);
	io_delay();
}

/*
 * Set up the GDT
 */

struct gdt_ptr {
	u16 len;
	u32 ptr;
} __attribute__((packed));

static void setup_gdt(void)
{
	/* There are machines which are known to not boot with the GDT
	   being 8-byte unaligned.  Intel recommends 16 byte alignment. */
	/// @zouyalong: GDT 元素必须是 16 字节对齐的。
	static const u64 boot_gdt[] __attribute__((aligned(16))) = {
		// GDT_ENTRY_BOOT_CS=2，前两个 gdt 元素是空，没有使用（第一个必须为空）。
		/* CS: code, read/execute, 4 GB, base 0 */
		[GDT_ENTRY_BOOT_CS] = GDT_ENTRY(0xc09b, 0, 0xfffff),
		/* DS: data, read/write, 4 GB, base 0 */
		[GDT_ENTRY_BOOT_DS] = GDT_ENTRY(0xc093, 0, 0xfffff),
		/* TSS: 32-bit tss, 104 bytes, base 4096 */
		/* We only have a TSS here to keep Intel VT happy;
		   we don't actually use it for anything. */
		// @zouyalong: 32 位 TSS， 104 字节，基地址为 4096。
		// 这里由于已经关了中断（null_idt），所以不会使用到 TSS。设置 TSS 只是为了让 Intel 处理器能正确进入保护模式。
		[GDT_ENTRY_BOOT_TSS] = GDT_ENTRY(0x0089, 4096, 103),
	};
	/* Xen HVM incorrectly stores a pointer to the gdt_ptr, instead
	   of the gdt_ptr contents.  Thus, make it static so it will
	   stay in memory, at least long enough that we switch to the
	   proper kernel GDT. */
	static struct gdt_ptr gdt;

	// @zouyalong: gdt 的长度及基地址。
	gdt.len = sizeof(boot_gdt)-1;
	gdt.ptr = (u32)&boot_gdt + (ds() << 4);// 此时还在实模式，简单运算。

	// 设置 GDT。
	asm volatile("lgdtl %0" : : "m" (gdt));
}

/*
 * Set up the IDT
 */
// @zouyalong: 清空 IDT。
static void setup_idt(void)
{
	static const struct gdt_ptr null_idt = {0, 0};
	asm volatile("lidtl %0" : : "m" (null_idt));
}

/*
 * Actual invocation sequence
 */
void go_to_protected_mode(void)
{
	/* Hook before leaving real mode, also disables interrupts */
	realmode_switch_hook();

	/* Enable the A20 gate */
	if (enable_a20()) {
		puts("A20 gate not responding, unable to boot...\n");
		die();
	}

	/* Reset coprocessor (IGNNE#) */
	reset_coprocessor();

	/* Mask all interrupts in the PIC */
	// @zouyalong: 屏蔽所有中断。
	mask_all_interrupts();

	/* Actual transition to protected mode... */
	// @zouyalong: 清空 IDT，设置 GDT，跳转到保护模式。
	setup_idt();
	setup_gdt();
	/// @zouyalong: 跳转到保护模式。代码在 pmjump.S 中。
	/// 两个参数：1. 保护模式下的代码入口；2. boot_params的地址。
	/// 参数分别放在 eax、edx 中。
	/// code32_start 指向 arch/x86/boot/compressed/head_64.S 的 startup_32
	protected_mode_jump(boot_params.hdr.code32_start,
			    (u32)&boot_params + (ds() << 4));
}
