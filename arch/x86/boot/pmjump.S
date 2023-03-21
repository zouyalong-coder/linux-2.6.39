/* ----------------------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

/*
 * The actual transition into protected mode
 */

#include <asm/boot.h>
#include <asm/processor-flags.h>
#include <asm/segment.h>
#include <linux/linkage.h>

	.text
	.code16

/*
 * void protected_mode_jump(u32 entrypoint, u32 bootparams);
 */
/// @zouyalong: 使用 fastcall 思想，参数分别放入 eax 寄存器和 edx 寄存器。TODO：怎么指定的寄存器？
GLOBAL(protected_mode_jump)
	movl	%edx, %esi		;# Pointer to boot_params table boot_params 地址放入 esi 寄存器

	; @zouyalong: 构造 C 调用约定的返回值
	xorl	%ebx, %ebx ; @zouyalong: ebx = 0
	; 将 cs 寄存器内容放入 bx 寄存器，接着执行 bx << 4 + 标号为2的代码的地址，这样一来 bx 寄存器就包含了标号为2的代码的地址。
	movw	%cs, %bx	; @zouyalong: bx = 0x10, 16 位的 cs 寄存器
	shll	$4, %ebx ; @zouyalong: 将ebx左移4位，ebx = 0x100
	addl	%ebx, 2f ; @zouyalong: ebx + 2f = 0x100 + 0x7c00 = 0x7d00
	jmp	1f			# Short jump to serialize on 386/486
1:

	movw	$__BOOT_DS, %cx	; @zouyalong：数据段放入 cx
	movw	$__BOOT_TSS, %di ; @zouyalong: TSS 段描述符放入 di 寄存器

	; 设置 PE 位，进入保护模式
	movl	%cr0, %edx
	orb	$X86_CR0_PE, %dl	# Protected mode
	movl	%edx, %cr0

	# Transition to 32-bit mode
	; 0x66 操作符前缀允许我们混合执行 16 位和 32 位代码
	; 0xea - 跳转指令的操作符
	.byte	0x66, 0xea		# ljmpl opcode ; jump __BOOT_CS:in_pm32. CS:IP 只能通过 ljmpl 指令设置
2:	.long	in_pm32			# offset
	.word	__BOOT_CS		# segment	; @zouyalong: __BOOT_CS 指向 GDT 的内核代码段描述符
ENDPROC(protected_mode_jump)

	.code32
	.section ".text32","ax"	; @zouyalong: ax 表示可读可执行(allocation  execute)
GLOBAL(in_pm32)
	# Set up data segments for flat 32-bit mode
	movl	%ecx, %ds	; 重置除 cs 外的所有寄存器，ecx 在上面代码中已经被设置为 __BOOT_DS
	movl	%ecx, %es
	movl	%ecx, %fs
	movl	%ecx, %gs
	movl	%ecx, %ss
	# The 32-bit code sets up its own stack, but this way we do have
	# a valid stack if some debugging hack wants to use it.
	addl	%ebx, %esp	; @zouyalong: esp = esp + ebx。将栈指针退回. 

	# Set up TR to make Intel VT happy
	ltr	%di

	# Clear registers to allow for future extensions to the
	# 32-bit boot protocol
	xorl	%ecx, %ecx ; 清空所有通用寄存器（除 eax）
	xorl	%edx, %edx
	xorl	%ebx, %ebx
	xorl	%ebp, %ebp
	xorl	%edi, %edi

	# Set up LDTR to make Intel VT happy
	lldt	%cx

	;eax            0x100000	1048576 ; arch/x86/boot/compressed/head_64.S 的 startup_32
	; ecx            0x0	    0
	; edx            0x0	    0
	; ebx            0x0	    0
	; esp            0x1ff5c	0x1ff5c
	; ebp            0x0	    0x0
	; esi            0x14470	83056
	; edi            0x0	    0
	; eip            0x100000	0x100000 ; 所有段基址都为 0，所以当前 CS:IP = 0x100000
	; eflags         0x46	    [ PF ZF ]
	; cs             0x10	16 ; gdt[2]
	; ss             0x18	24	; gdt[3]
	; ds             0x18	24
	; es             0x18	24
	; fs             0x18	24
	; gs             0x18	24

	jmpl	*%eax			; Jump to the 32-bit entrypoint，进入 32 位模式入口，即 start_kernel(bzImage时：0x100000)。跳转到 eax 指向的地址。
ENDPROC(in_pm32)
