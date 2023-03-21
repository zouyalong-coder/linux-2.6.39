/* ----------------------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

#include <linux/linkage.h>

/*
 * Memory copy routines
 */

	.code16gcc
	.text

GLOBAL(memcpy)
	pushw	%si
	pushw	%di
	movw	%ax, %di
	movw	%dx, %si
	pushw	%cx
	shrw	$2, %cx
	rep; movsl
	popw	%cx
	andw	$3, %cx
	rep; movsb
	popw	%di
	popw	%si
	ret
ENDPROC(memcpy)

GLOBAL(memset)
	pushw	%di
	movw	%ax, %di
	movzbl	%dl, %eax
	imull	$0x01010101,%eax	; @zouyalong: 乘上 0x01010101.原因是代码每次将尝试拷贝4个字节内存的内容。假设我们需要将 0x7 这个数值放到内存中，在执行 imull 指令之前，eax 寄存器的值是 0x7，在 imull 指令被执行之后，eax 寄存器的内容变成了 0x07070707（4个字节的 0x7）。在 imull 指令之后，代码使用 rep; stosl 指令将 eax 寄存器的内容拷贝到 es:di 指向的内存。 todo: 为什么要乘上 0x01010101？
	pushw	%cx
	shrw	$2, %cx
	rep; stosl
	popw	%cx
	andw	$3, %cx
	rep; stosb
	popw	%di
	ret
ENDPROC(memset)

GLOBAL(copy_from_fs)
	pushw	%ds
	pushw	%fs
	popw	%ds
	call	memcpy
	popw	%ds
	ret
ENDPROC(copy_from_fs)

GLOBAL(copy_to_fs)
	pushw	%es
	pushw	%fs
	popw	%es
	call	memcpy
	popw	%es
	ret
ENDPROC(copy_to_fs)

#if 0 /* Not currently used, but can be enabled as needed */
GLOBAL(copy_from_gs)
	pushw	%ds
	pushw	%gs
	popw	%ds
	call	memcpy
	popw	%ds
	ret
ENDPROC(copy_from_gs)

GLOBAL(copy_to_gs)
	pushw	%es
	pushw	%gs
	popw	%es
	call	memcpy
	popw	%es
	ret
ENDPROC(copy_to_gs)
#endif
