/*
 *  linux/boot/head.S
 *
 *  Copyright (C) 1991, 1992, 1993  Linus Torvalds
 */

/*
 *  head.S contains the 32-bit startup code.
 *
 * NOTE!!! Startup happens at absolute address 0x00001000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory. [According to comments etc elsewhere on a compressed
 * kernel it will end up at 0x1000 + 1Mb I hope so as I assume this. - AC]
 *
 * Page 0 is deliberately kept safe, since System Management Mode code in 
 * laptops may need to access the BIOS data stored there.  This is also
 * useful for future device drivers that either access the BIOS via VM86 
 * mode.
 */
 ; @zouyalong: 注意，compressed 表示kernel倍压缩为了 bzImage，此文件的主要目的是做好长模式（64位）准备后，解压kernel，并跳转到解压后的kernel入口点。

/*
 * High loaded stuff by Hans Lermen & Werner Almesberger, Feb. 1996
 */
 ; @zouyalong: 此时代码仍然在 32位模式
	.code32
	.text

#include <linux/init.h>
#include <linux/linkage.h>
#include <asm/segment.h>
#include <asm/pgtable_types.h>
#include <asm/page_types.h>
#include <asm/boot.h>
#include <asm/msr.h>
#include <asm/processor-flags.h>
#include <asm/asm-offsets.h>

	__HEAD	;@zouyalong include/linux/init.h .section	".head.text","ax"。在 setup.ld 中，.head.text
	.code32
ENTRY(startup_32)
	cld	; @zouyalong cld 指令将标志寄存器的 DF （方向标志）位清空。当方向标志被清空，所有的串操作指令像stos， scas等等将会增加索引寄存器 esi 或者 edi 的值。我们需要清空方向标志是因为接下来我们会使用汇编的串操作指令来做为页表腾出空间等工作。
	/*
	 * Test KEEP_SEGMENTS flag to see if the bootloader is asking
	 * us to not reload segments
	 */
	testb $(1<<6), BP_loadflags(%esi)	; 从内核加载头中的 loadflags 字段来检查 KEEP_SEGMENTS 标志。
	; @zouyalong: 第 6 位 (写): KEEP_SEGMENTS
	;   协议版本: 2.07+
	;   - 为0，在32位入口点重载段寄存器
	;   - 为1，不在32位入口点重载段寄存器。假设 %cs %ds %ss %es 都被设到基地址为0的普通段中（或者在他们的环境中等价的位置）。
	jnz 1f

	cli
	; 在 arch/x86/boot/pmjump.S 中切换到保护模式的时候已经更新了这些段寄存器。那么为什么我们还要去关心这些段寄存器的值呢？答案很简单，Linux 内核也有32位的引导协议，如果一个引导程序之前使用32位协议引导内核，那么在 startup_32 之前的代码就会被忽略。在这种情况下 startup_32 将会变成引导程序之后的第一个入口点，不保证段寄存器会不会处于未知状态。
	movl	$(__KERNEL_DS), %eax
	movl	%eax, %ds
	movl	%eax, %es
	movl	%eax, %ss
1:

/*
 * Calculate the delta between where we were compiled to run
 * at and where we were actually loaded at.  This can only be done
 * with a short local call on x86.  Nothing  else will tell us what
 * address we are running at.  The reserved chunk of the real-mode
 * data at 0x1e4 (defined as a scratch field) are used as the stack
 * for this calculation. Only 4 bytes are needed.
 */
	; @zouyalong: 当前 esi 中存了 boot_param（在pmjump.S中设置）
	leal	(BP_scratch+4)(%esi), %esp
	; 通过 call 指令会将返回地址压入栈中的特性，我们就可以得到 1f 的地址，再 popl 就将 1f 的物理地址放入了 ebp 中。+4是因为栈是自顶向下生长的，所以我们需要把栈指针指向栈顶。
	call	1f	; @zouyalong: bootparams 这个结构体包含了一个特殊的字段 scratch ，其偏移量为 0x1e4 。这个 4 字节的区域将会成为 call 指令的临时栈。我们把 scratch 的地址加 4 存入 esp 寄存器。我们之所以在 BP_scratch 基础上加 4 是因为，如之前所说的，这将成为一个临时的栈，而在 x86_64 架构下，栈是自顶向下生长的。所以我们的栈指针就会指向栈顶
1:	popl	%ebp	; 跳转到 1f 标签并且把该标签的地址放入 ebp 寄存器，因为在执行 call 指令之后我们把返回地址放到了栈顶。那么，目前我们拥有 1f 标签的地址，也能够很容易得到 startup_32 的地址。我们只需要把我们从栈里得到的地址减去标签的地址：
	subl	$1b, %ebp ; 从 ebp 中减去 1f ，我们就会得到 startup_32 的实际物理地址。由于在链接时，startup_32 地址是0，所以加上 ebp 中的值就是我们的偏移量。

/* setup a stack and make sure cpu supports long mode. */
	; @zouyalong: arch/x86/boot/compressed/head_64.S 中的 boot_stack_end 定义，位于bss
	movl	$boot_stack_end, %eax	; eax 寄存器将包含 boot_stack_end 链接后的地址或者说 0x0 + boot_stack_end
	addl	%ebp, %eax	; 加上物理地址偏移量，就得到了正确的栈
	movl	%eax, %esp

	; @zouyalong: arch/x86/kernel/verify_cpu.S
	call	verify_cpu	; 检查 CPU 是否支持 长模式 和 SSE
	testl	%eax, %eax 	; 如果 eax 的值不是 0 ，那么就跳转到 no_longmode 标签
	jnz	no_longmode

/*
 * Compute the delta between where we were compiled to run at
 * and where the code will actually run at.
 *
 * %ebp contains the address we are loaded at by the boot loader and %ebx
 * contains the address where we should move the kernel image temporarily
 * for safe in-place decompression.
 */
;这建立了一个保留了重定向信息的内核镜像，这样就可以在默认的 1MB 位置之外加载了。

;注意：如果 CONFIG_RELOCATABLE=y， 那么 内核将会从其被加载的位置运行，编译时的物理地址 (CONFIG_PHYSICAL_START) 将会被作为最低地址位置的限制。
; 内核使用 PIC (Position Independent Code) 机制，所以它可以被加载到任何位置。
#ifdef CONFIG_RELOCATABLE
	movl	%ebp, %ebx	; @zouyalong: ebp 中是 startup_32 的物理地址
	movl	BP_kernel_alignment(%esi), %eax ; 注意，此时 esi 是
	decl	%eax	; 如果在内核配置中 CONFIG_RELOCATABLE 内核配置项开启，我们就把这个地址放到 ebx 寄存器中，对齐到 2M 的整数倍 ，然后和 LOAD_PHYSICAL_ADDR 的值比较
	addl	%eax, %ebx
	notl	%eax
	andl	%eax, %ebx
#else
	movl	$LOAD_PHYSICAL_ADDR, %ebx
#endif

	/* Target address to relocate to for decompression */
	addl	$z_extract_offset, %ebx	; @zouyalong: ebx 此时是内核解压后的实际地址。

/*
 * Prepare for entering 64 bit mode
 */

	/* Load new GDT with the 64bit segments using 32bit descriptor */
	leal	gdt(%ebp), %eax	; @zouyalong: ebp 中是内核的物理地址
	movl	%eax, gdt+2(%ebp) ; gdt_desc 的地址表示的是 GDT 的入口地址，这里写入了正确的地址
	lgdt	gdt(%ebp)	; 加载 lgdt

	/* Enable PAE mode */
	movl	$(X86_CR4_PAE), %eax
	movl	%eax, %cr4


; @zouyalong: 长模式是 x86_64 系列处理器的原生模式。x86_64 和 x86 的一些区别。

; 64位 模式提供了一些新特性，比如：

; 从 r8 到 r15 8个新的通用寄存器，并且所有通用寄存器都是64位的了。
; 64位指令指针 - RIP ;
; 新的操作模式 - 长模式;
; 64位地址和操作数;
; RIP 相对寻址 (我们将会在接下来的章节看到一个例子).
; 长模式是一个传统保护模式的扩展，其由两个子模式构成：

; 64位模式
; 兼容模式
; 为了切换到 64位 模式，我们需要完成以下操作：

; 启用 PAE;
; 建立页表并且将顶级页表的地址放入 cr3 寄存器;
; 启用 EFER.LME ;
; 启用分页;

 /*
  * Build early 4G boot pagetable
  4G 启动页表
  */
;   Linux 内核使用 4级 页表，通常我们会建立6个页表：

; 1 个 PML4 或称为 4级页映射 表，包含 1 个项；
; 1 个 PDP 或称为 页目录指针 表，包含 4 个项；
; 4 个 页目录表，一共包含 2048 个项；
; 目前 ebx 中是内核的物理地址偏移量
	/* Initialize Page tables to 0 */
	leal	pgtable(%ebx), %edi	; 清空页表.
	xorl	%eax, %eax
	movl	$((4096*6)/4), %ecx	; 每个表都是 4096 字节，所以我们需要 24 KB 的空间
	rep	stosl

	; The leal (load effective address) instruction computes the final memory address according to the addressing mode, and stores the result in a register. For example, leal 5(%eax,%ebx,8), %ecx means ecx = eax + ebx*8 + 5;. Note that this is entirely an arithmetic operation and does not involve dereferencing a memory address.
	; lea 指令只计算，不进行内存访问。
	/* Build Level 4, PML4, 顶级页表 */
	leal	pgtable + 0(%ebx), %edi	; edi 是patable 的物理地址。指向patable +0 位置，第一页。
	leal	0x1007 (%edi), %eax	; eax = ((*page)patable)[0] + 0x1007。0x1007 是 PML4 的大小 4096 加上 7 。这里的 7 代表了 PML4 的项标记。在我们这里，这些标记是 PRESENT+RW+USER 。eax 是 patable + 0x1007，其中 4096 是PML本身的大小 4KB
	movl	%eax, 0(%edi)	; @zouyalong: 写入表项。

	/* Build Level 3 */
	leal	pgtable + 0x1000(%ebx), %edi; 指向 patable+4KB 的位置，即第二页
	leal	0x1007(%edi), %eax; *eax = ((*page)patable)[1] + 0x1007。0x1007 表示底12位是0x007
	movl	$4, %ecx
1:	movl	%eax, 0x00(%edi); *edi = eax
	addl	$0x00001000, %eax; eax += 0x00001000; eax 指向下一页
	addl	$8, %edi; edi += 8 // 下一元素
	decl	%ecx; ecx--
	jnz	1b ; if ecx > 0: goto 1

	/* Build Level 2 */
	leal	pgtable + 0x2000(%ebx), %edi; edi = ((*page)patable)[2]
	movl	$0x00000183, %eax	; eax =0x00000183 
	movl	$2048, %ecx ; ecx = 2KB
1:	movl	%eax, 0(%edi)	; *edi = eax
	addl	$0x00200000, %eax	; eax += 0x00200000
	addl	$8, %edi	; edi += 8 // 每8字节复制一次
	decl	%ecx	; ecx -= 1
	jnz	1b

	/* Enable the boot page tables */
	leal	pgtable(%ebx), %eax	; eax = patable
	movl	%eax, %cr3	; cr3 = patable, 设置页表*物理*地址（注意没加上 ebx 虚拟地址偏移）。

	/* Enable Long mode in EFER (Extended Feature Enable Register) */
	; @zouyalong: arch/x86/include/uapi/asm/msr-index.h 中定义。
	movl	$MSR_EFER, %ecx
	rdmsr	; 读取 msr 寄存器。在 rdmsr 执行之后，我们将会获得 edx:eax 中的结果值，其取决于 ecx 的值。
	btsl	$_EFER_LME, %eax	; 通过 btsl 指令检查 EFER_LME 位，并且通过 wrmsr 指令将 eax 的数据写入 MSR 寄存器。
	wrmsr	; 将 eax 的数据写入 MSR 寄存器。

	/*
	 * Setup for the jump to 64bit mode
	 *
	 * When the jump is performend we will be in long mode but
	 * in 32bit compatibility mode with EFER.LME = 1, CS.L = 0, CS.D = 1
	 * (and in turn EFER.LMA = 1).	To jump into 64bit mode we use
	 * the new gdt/idt that has __KERNEL_CS with CS.L = 1.
	 * We place all of the values on our mini stack so lret can
	 * used to perform that far jump.
	 */
	 ; @zouyalong: 伪造调用栈，为 lret 做准备。lret 开始进入 64 为运行模式。
	 ; 由于 lret 会出栈 ECS:EIP 组合，所以
	pushl	$__KERNEL_CS 	; 先压 CS. KERNEL_CS 段选择子对应的工作模式已经是 64位了
	leal	startup_64(%ebp), %eax	; 计算 startup_64 的逻辑（虚拟）位置
	pushl	%eax	; 将 startup_64 作为 ra

	/* Enter paged protected Mode, activating Long Mode */
	movl	$(X86_CR0_PG | X86_CR0_PE), %eax /* Enable Paging and Protected mode */
	movl	%eax, %cr0

	/* Jump from 32bit compatibility mode into 64bit mode. */
	lret ; 根据 CS 的工作模式，就会进入 64 位模式运行。
ENDPROC(startup_32)

no_longmode:
	/* This isn't an x86-64 CPU so hang */
1:
	hlt
	jmp     1b

#include "../../kernel/verify_cpu.S"

	/*
	 * Be careful here startup_64 needs to be at a predictable
	 * address so I can export it in an ELF header.  Bootloaders
	 * should look at the ELF header to find this address, as
	 * it may change in the future.
	 */
	.code64
	.org 0x200
ENTRY(startup_64)
	/*
	 * We come here either from startup_32 or directly from a
	 * 64bit bootloader.  If we come here from a bootloader we depend on
	 * an identity mapped page table being provied that maps our
	 * entire text+data+bss and hopefully all of memory.
	 */

	/* Setup data segments. */
	xorl	%eax, %eax
	movl	%eax, %ds	; @zouyalong: 所有段寄存器（cs外）清零
	movl	%eax, %es
	movl	%eax, %ss
	movl	%eax, %fs
	movl	%eax, %gs
	lldt	%ax
	movl    $0x20, %eax
	ltr	%ax

	/*
	 * Compute the decompressed kernel start address.  It is where
	 * we were loaded at aligned to a 2M boundary. %rbp contains the
	 * decompressed kernel start address.
	 *
	 * If it is a relocatable kernel then decompress and run the kernel
	 * from load address aligned to 2MB addr, otherwise decompress and
	 * run the kernel from LOAD_PHYSICAL_ADDR
	 *
	 * We cannot rely on the calculation done in 32-bit mode, since we
	 * may have been invoked via the 64-bit entry point.
	 */

	/* Start with the delta to where the kernel will run at. */
	; @zouyalong: 计算内核编译时的位置和它被加载的位置的差
#ifdef CONFIG_RELOCATABLE
	leaq	startup_32(%rip) /* - $startup_32 */, %rbp	; @zouyalong: rbp 中是内核起始地址
	movl	BP_kernel_alignment(%rsi), %eax
	decl	%eax
	addq	%rax, %rbp
	notq	%rax
	andq	%rax, %rbp
#else
	movq	$LOAD_PHYSICAL_ADDR, %rbp
#endif

	/* Target address to relocate to for decompression */
	leaq	z_extract_offset(%rbp), %rbx

	/* Set up the stack */
	leaq	boot_stack_end(%rbx), %rsp

	/* Zero EFLAGS */
	pushq	$0
	popfq	; @zouyalong: 清空标志寄存器。

/*
 * Copy the compressed kernel to the end of our buffer
 * where decompression in place becomes safe.
 */
	pushq	%rsi
	leaq	(_bss-8)(%rip), %rsi	; rsi包含_bss - 8的绝对地址，rdi包含_bss - 8的重定位的相对地址。
	leaq	(_bss-8)(%rbx), %rdi
	movq	$_bss /* - $startup_32 */, %rcx
	shrq	$3, %rcx
	std	; 设置DF标志，意味着rsi和rdi会递减
	rep	movsq	; 
	cld	; 清除DF标志
	popq	%rsi

/*
 * Jump to the relocated address.
 */
	leaq	relocated(%rbx), %rax	; .text节的重定位后的地址
	jmp	*%rax

; @zouyalong: 内核解压前的最后准备
	.text
relocated:

/*
 * Clear BSS (stack is currently empty)
 */
	xorl	%eax, %eax
	leaq    _bss(%rip), %rdi
	leaq    _ebss(%rip), %rcx
	subq	%rdi, %rcx
	shrq	$3, %rcx
	rep	stosq

/*
 * Adjust our own GOT
 */
	leaq	_got(%rip), %rdx
	leaq	_egot(%rip), %rcx
1:
	cmpq	%rcx, %rdx
	jae	2f
	addq	%rbx, (%rdx)
	addq	$8, %rdx
	jmp	1b
2:
	
/*
 * Do the decompression, and jump to the new kernel..
 */
 ; @zouyalong: 参数通过 http://www.x86-64.org/documentation/abi.pdf System V ABI 传递。
	pushq	%rsi			/* Save the real mode argument */
	movq	%rsi, %rdi		/* real mode address */; @zouyalong: 设置rdi为指向boot_params结构体的指针并把它保存到栈中
	leaq	boot_heap(%rip), %rsi	/* malloc area for uncompression */
	leaq	input_data(%rip), %rdx  /* input_data */
	movl	$z_input_len, %ecx	/* input_len */
	movq	%rbp, %r8		/* output target address */
	call	decompress_kernel
	popq	%rsi

/*
 * Jump to the decompressed kernel.
 */
	jmp	*%rbp	; @zouyalong: 跳转到解压后的地址。(arch/x86/kernel/head_64.S)startup_64，在 arch/x86/kernel/vmlinux.lds.S 中指定在 kernel 开始处。

; @zouyalong: 位于 .data 段，并且包含了5个描述符： null 、内核代码段、内核数据段和其他两个任务描述符。我们已经在上一章节载入了 全局描述符表 ，和我们现在做的差不多，但是将描述符改为 CS.L = 1 CS.D = 0 从而在 64 位模式下执行。我们可以看到， gdt 的定义从两个字节开始： gdt_end - gdt ，代表了 gdt 表的最后一个字节，或者说表的范围。接下来的4个字节包含了 gdt 的基地址。记住 全局描述符表 保存在 48位 GDTR-全局描述符表寄存器 中，由两个部分组成：

; 全局描述符表的大小 (16位）
; 全局描述符表的基址 (32位)

	.data
gdt:
	.word	gdt_end - gdt	; gdt 的长度
	.long	gdt 	; gdt 起始地址，上面会写入加上偏移的地址。
	.word	0
	.quad	0x0000000000000000	/* NULL descriptor */
	.quad	0x00af9a000000ffff	/* __KERNEL_CS, 将描述符改为 CS.L = 1 CS.D = 0 从而在 64 位模式下执行 */
	.quad	0x00cf92000000ffff	/* __KERNEL_DS */
	.quad	0x0080890000000000	/* TS descriptor */
	.quad   0x0000000000000000	/* TS continued */
gdt_end:

/*
 * Stack and heap for uncompression
 */
	.bss
	.balign 4
boot_heap:
	.fill BOOT_HEAP_SIZE, 1, 0
boot_stack:
	.fill BOOT_STACK_SIZE, 1, 0
boot_stack_end:

/*
 * Space for page tables (not in .bss so not zeroed)
 */
	.section ".pgtable","a",@nobits
	.balign 4096
pgtable:
	.fill 6*4096, 1, 0
