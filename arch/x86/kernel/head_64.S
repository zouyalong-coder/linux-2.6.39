/*
 *  linux/arch/x86_64/kernel/head.S -- start in 32bit and switch to 64bit
 *
 *  Copyright (C) 2000 Andrea Arcangeli <andrea@suse.de> SuSE
 *  Copyright (C) 2000 Pavel Machek <pavel@suse.cz>
 *  Copyright (C) 2000 Karsten Keil <kkeil@suse.de>
 *  Copyright (C) 2001,2002 Andi Kleen <ak@suse.de>
 *  Copyright (C) 2005 Eric Biederman <ebiederm@xmission.com>
 */


#include <linux/linkage.h>
#include <linux/threads.h>
#include <linux/init.h>
#include <asm/segment.h>
#include <asm/pgtable.h>
#include <asm/page.h>
#include <asm/msr.h>
#include <asm/cache.h>
#include <asm/processor-flags.h>
#include <asm/percpu.h>

#ifdef CONFIG_PARAVIRT
#include <asm/asm-offsets.h>
#include <asm/paravirt.h>
#else
#define GET_CR2_INTO_RCX movq %cr2, %rcx
#endif

/* we are not able to switch in one step to the final KERNEL ADDRESS SPACE
 * because we need identity-mapped pages.
 *
 */

#define pud_index(x)	(((x) >> PUD_SHIFT) & (PTRS_PER_PUD-1))

L4_PAGE_OFFSET = pgd_index(__PAGE_OFFSET)
L3_PAGE_OFFSET = pud_index(__PAGE_OFFSET)
L4_START_KERNEL = pgd_index(__START_KERNEL_map)
L3_START_KERNEL = pud_index(__START_KERNEL_map)

	.text
	__HEAD
	.code64
	.globl startup_64
startup_64:

	/*
	 * At this point the CPU runs in 64bit mode CS.L = 1 CS.D = 1,
	 * and someone has loaded an identity mapped page table
	 * for us.  These identity mapped page tables map all of the
	 * kernel pages and possibly all of memory.
	 *
	 * %esi holds a physical pointer to real_mode_data.
	 *
	 * We come here either directly from a 64bit bootloader, or from
	 * arch/x86_64/boot/compressed/head.S.
	 *
	 * We only come here initially at boot nothing else comes here.
	 *
	 * Since we may be loaded at an address different from what we were
	 * compiled to run at we first fixup the physical addresses in our page
	 * tables and then reload them.
	 */

	/* Compute the delta between the address I am compiled to run at and the
	 * address I am actually running at.
	 @zouyalong：计算逻辑地址（编译）和加载的虚拟地址
	 */
	; rbp = 0x1000000 - (0xffffffff81000000 - 0xffffffff80000000) = 0. 代表了实际加载地址与编译后的默认地址之间的差值。在我们这个例子中，0 代表了 Linux 内核被加载到了默认地址，并且没有启用 kASLR 。如果启用了 kASLR ，则这个差值将不为 0 ，并且将会影响到后面的内核初始化过程。
	leaq	_text(%rip), %rbp	; _text 在链接脚本中定义（arch/x86/kernel/vmlinux.lds.S），表示内核的起始逻辑地址
	subq	$_text - __START_KERNEL_map, %rbp; 计算 0x1000000 与实际加载地址的差。这里我们首先将RIP相对地址（rip-relative）放入 rbp 寄存器，并且从中减去 $_text - __START_KERNEL_map 。我们已经知道， _text 在编译后的默认虚拟地址为 0xffffffff81000000， 物理地址为 0x1000000。__START_KERNEL_map 宏将展开为 0xffffffff80000000，因此对于对于第二行汇编代码，我们将得到如下的表达式

	/* Is the address not 2M aligned? */
	movq	%rbp, %rax
	andl	$~PMD_PAGE_MASK, %eax	; 确定地址是否对齐
	testl	%eax, %eax
	jnz	bad_address

	/* Is the address too large? */
	leaq	_text(%rip), %rdx ; @zouyalong: 地址不能过大（超过。。。）
	movq	$PGDIR_SIZE, %rax
	cmpq	%rax, %rdx
	jae	bad_address

	; @zouyalong: 在开始设置 Identity 分页之前，我们需要首先修正下面的物理地址：实际上就是对页表中的项加上内核加载的偏移量
	/* Fixup the physical addresses in the page table
	 */
	addq	%rbp, init_level4_pgt + 0(%rip)	; *init_level4_pgt[0] += rbp// 即把页表中原来设置的物理地址加上内核加载的偏移量
	addq	%rbp, init_level4_pgt + (L4_PAGE_OFFSET*8)(%rip)
	addq	%rbp, init_level4_pgt + (L4_START_KERNEL*8)(%rip)

	addq	%rbp, level3_ident_pgt + 0(%rip)

	addq	%rbp, level3_kernel_pgt + (510*8)(%rip)
	addq	%rbp, level3_kernel_pgt + (511*8)(%rip)

	addq	%rbp, level2_fixmap_pgt + (506*8)(%rip)

	/* Add an Identity mapping if I am above 1G */
	leaq	_text(%rip), %rdi ; 把_text的地址放入rdi
	andq	$PMD_PAGE_MASK, %rdi	; 对齐

	movq	%rdi, %rax
	shrq	$PUD_SHIFT, %rax	; @zouyalong: 为了得到这条索引，我们把 _text 的地址右移 PGDIR_SHIFT(39) 位。
	andq	$(PTRS_PER_PUD - 1), %rax	; 9个位，即512个页目录项，每个项8字节，共4096字节，即1页，通过这个就得到了 _text 的 PUD 偏移量（512项）。rax = offset_in_pud(_text)
	jz	ident_complete

	leaq	(level2_spare_pgt - __START_KERNEL_map + _KERNPG_TABLE)(%rbp), %rdx	; rdx= level2_spare_pgt	物理地址
	leaq	level3_ident_pgt(%rip), %rbx; rbx = level3_ident_pgt
	movq	%rdx, 0(%rbx, %rax, 8)	; level3_ident_pgt + 8 * offset_in_pud(_text) = level2_spare_pgt

	; rdi = &_text
	movq	%rdi, %rax
	shrq	$PMD_SHIFT, %rax
	andq	$(PTRS_PER_PMD - 1), %rax
	leaq	__PAGE_KERNEL_IDENT_LARGE_EXEC(%rdi), %rdx	; rdx = __PAGE_KERNEL_IDENT_LARGE_EXEC
	leaq	level2_spare_pgt(%rip), %rbx
	movq	%rdx, 0(%rbx, %rax, 8)
ident_complete:

	/*
	 * Fixup the kernel text+data virtual addresses. Note that
	 * we might write invalid pmds, when the kernel is relocated
	 * cleanup_highmap() fixes this up along with the mappings
	 * beyond _end.
	 */


	; 首先把 level2_kernel_pgt 的地址赋值给 rdi，并把页表项的地址赋值给 r8 寄存器
	leaq	level2_kernel_pgt(%rip), %rdi
	leaq	4096(%rdi), %r8	; r8 = level2_kernel_pgt + 4096
	/* See if it is a valid page table entry */
1:	testq	$1, 0(%rdi)	; 检查 level2_kernel_pgt 中的存在位，如果其为0，就把 rdi 加上8以便指向下一个页。
	jz	2f	; if level2_kernel_pgt[0] == 0, goto 2
	addq	%rbp, 0(%rdi)	; else level2_kernel_pgt[4096] = rbp = &_text
	/* Go to the next page */
2:	addq	$8, %rdi; 如果其为0，就把 rdi 加上8以便指向下一个页。
	cmp	%r8, %rdi
	jne	1b	; 将其与 r8（即页表项的地址）作比较，不相等的话就跳转回前面的标签 1 ，反之则继续运行。

	/* Fixup phys_base */
	; 其中 phys_base 与 level2_kernel_pgt 第一项相同，为 512 MB的内核映射。
	addq	%rbp, phys_base(%rip) ; 使用 rbp （即 _text 的物理地址）来修正 phys_base 物理地址。将 early_level4_pgt 的物理地址与 rbp 相加，然后跳转至标签 1

	/* Fixup trampoline */
	addq	%rbp, trampoline_level4_pgt + 0(%rip)
	addq	%rbp, trampoline_level4_pgt + (511*8)(%rip)

	/* Due to ENTRY(), sometimes the empty space gets filled with
	 * zeros. Better take a jmp than relying on empty space being
	 * filled with 0x90 (nop)
	 */
	jmp secondary_startup_64
ENTRY(secondary_startup_64)
	/*
	 * At this point the CPU runs in 64bit mode CS.L = 1 CS.D = 1,
	 * and someone has loaded a mapped page table.
	 *
	 * %esi holds a physical pointer to real_mode_data.
	 *
	 * We come here either from startup_64 (using physical addresses)
	 * or from trampoline.S (using virtual addresses).
	 *
	 * Using virtual addresses from trampoline.S removes the need
	 * to have any identity mapped pages in the kernel page table
	 * after the boot processor executes this code.
	 */

	/* Enable PAE mode and PGE */
	;@zouyalong 开启 PAE 和 PGE （Paging Global Extension），并且将phys_base的物理地址（见上）放入 rax 就寄存器，同时将其放入 cr3 寄存器
	movl	$(X86_CR4_PAE | X86_CR4_PGE), %eax
	movq	%rax, %cr4

	/* Setup early boot stage 4 level pagetables. */
	movq	$(init_level4_pgt - __START_KERNEL_map), %rax
	addq	phys_base(%rip), %rax; phys_base 在上面已经被修正过了
	movq	%rax, %cr3	; 页表基址寄存器 cr3 = init_level4_pgt - __START_KERNEL_map + phys_base

	/* Ensure I am executing from virtual addresses */
	movq	$1f, %rax
	jmp	*%rax
1:

	/* Check if nx is implemented */
	; 检查CPU是否支持 NX 位
	movl	$0x80000001, %eax
	cpuid	; 执行 cpuid 指令来得到处理器信息。这条指令的结果会存放在 edx 中，我们把他再放到 edi 里
	movl	%edx,%edi

	/* Setup EFER (Extended Feature Enable Register) */
	movl	$MSR_EFER, %ecx	; 把 MSR_EFER （即 0xc0000080）放入 ecx
	rdmsr	; 执行 rdmsr 指令来读取CPU中的Model Specific Register (MSR), 返回结果将存放于 edx:eax 
; 63                                                                              32
;  --------------------------------------------------------------------------------
; |                                                                               |
; |                                Reserved MBZ                                   |
; |                                                                               |
;  --------------------------------------------------------------------------------
; 31                            16  15      14      13   12  11   10  9  8 7  1   0
;  --------------------------------------------------------------------------------
; |                              | T |       |       |    |   |   |   |   |   |   |
; | Reserved MBZ                 | C | FFXSR | LMSLE |SVME|NXE|LMA|MBZ|LME|RAZ|SCE|
; |                              | E |       |       |    |   |   |   |   |   |   |
;  --------------------------------------------------------------------------------
	btsl	$_EFER_SCE, %eax	/* Enable System Call */; 将 _EFER_SCE （即第0位）置1，设置 SCE 位将会启用 SYSCALL 以及 SYSRET 指令。
	btl	$20,%edi		/* No Execute supported? */; ;检查 edi（即 cpuid 的结果（见上）） 中的第20位。如果第 20 位（即 NX 位）置位，我们就只把 EFER_SCE写入MSR。
	jnc     1f
	btsl	$_EFER_NX, %eax	; 如果支持 NX 那么我们就把 _EFER_NX 也写入MSR。
1:	wrmsr				/* Make changes effective */; 写回 edx:eax 寄存器中的值到 MSR 中

	/* Setup cr0 */
; X86_CR0_PE - 系统处于保护模式;
; X86_CR0_MP - 与CR0的TS标志位一同控制 WAIT/FWAIT 指令的功能；
; X86_CR0_ET - 386允许指定外部数学协处理器为80287或80387;
; X86_CR0_NE - 如果置位，则启用内置的x87浮点错误报告，否则启用PC风格的x87错误检测；
; X86_CR0_WP - 如果置位，则CPU在特权等级为0时无法写入只读内存页;
; X86_CR0_AM - 当AM位置位、EFLGS中的AC位置位、特权等级为3时，进行对齐检查;
; X86_CR0_PG - 启用分页.
#define CR0_STATE	(X86_CR0_PE | X86_CR0_MP | X86_CR0_ET | \
			 X86_CR0_NE | X86_CR0_WP | X86_CR0_AM | \
			 X86_CR0_PG)
	movl	$CR0_STATE, %eax
	/* Make changes effective */
	movq	%rax, %cr0	; 设置 cr0

	/* Setup a boot time stack */
	; 为了从汇编执行C语言代码，我们需要建立一个栈。
	movq stack_start(%rip),%rsp	; 首先将栈指针 指向一个内存中合适的区域，然后重置FLAGS寄存器

	/* zero EFLAGS after setting rsp */
	pushq $0
	popfq	; pop to flags

	/*
	 * We must switch to a new descriptor in kernel space for the GDT
	 * because soon the kernel won't have access anymore to the userspace
	 * addresses where we're currently running on. We have to do that here
	 * because in 32bit we couldn't load a 64bit linear address.
	 */
	lgdt	early_gdt_descr(%rip)	; @zouyalong 加载 GDT。需要重新加载 全局描述附表 的原因是，虽然目前内核工作在用户空间的低地址中，但很快内核将会在它自己的内存地址空间中运行。

	/* set up data segments */
	xorl %eax,%eax
	movl %eax,%ds
	movl %eax,%ss
	movl %eax,%es

	/*
	 * We don't really need to load %fs or %gs, but load them anyway
	 * to kill any stale realmode selectors.  This allows execution
	 * under VT hardware.
	 */
	movl %eax,%fs
	movl %eax,%gs

	/* Set up %gs.
	 *
	 * The base of %gs always points to the bottom of the irqstack
	 * union.  If the stack protector canary is enabled, it is
	 * located at %gs:40.  Note that, on SMP, the boot cpu uses
	 * init data section till per cpu areas are set up.
	 */
	movl	$MSR_GS_BASE,%ecx	; 把 MSR_GS_BASE （即 0xc0000101）放入 ecx
	movl	initial_gs(%rip),%eax
	movl	initial_gs+4(%rip),%edx
	wrmsr	; 向 eax 和 edx 处的地址加载数据（即指向 initial_gs）。
	; cs, fs, ds 和 ss 段寄存器在64位模式下不用来寻址，但 fs 和 gs 可以使用。 fs 和 gs 有一个隐含的部分（与实模式下的 cs 段寄存器类似），这个隐含部分存储了一个描述符，其指向 Model Specific Registers。因此上面的 0xc0000101 是一个 gs.base MSR 地址。当发生系统调用 或者 中断时，入口点处并没有内核栈，因此 MSR_GS_BASE 将会用来存放中断栈。在中断处理程序中，我们可以通过 gs.base 来访问中断栈。

	/* esi is pointer to real mode structure with interesting info.
	   pass it to C */
	movl	%esi, %edi	; 把实模式中的 bootparam 结构的地址放入 rdi (要记得 rsi 从一开始就保存了这个结构体的指针)
	
	/* Finally jump to run C code and to be on real kernel address
	 * Since we are running on identity-mapped space we have to jump
	 * to the full 64bit address, this is only possible as indirect
	 * jump.  In addition we need to ensure %cs is set so we make this
	 * a far return.
	 */
	movq	initial_code(%rip),%rax	; x86_64_start_kernel()
	pushq	$0		# fake return address to stop unwinder
	pushq	$__KERNEL_CS	# set correct cs
	pushq	%rax		# target address in negative space
	lretq	; 使用 lretq 指令来跳转到 x86_64_start_kernel() 函数。不使用 jump、call的原因是要保证 cs 的正确性。

	/* SMP bootup changes these two */
	__REFDATA
	.align	8
	ENTRY(initial_code)
	.quad	x86_64_start_kernel
	ENTRY(initial_gs)
	.quad	INIT_PER_CPU_VAR(irq_stack_union)

	ENTRY(stack_start)
	.quad  init_thread_union+THREAD_SIZE-8	; 为了从汇编执行C语言代码，我们需要建立一个栈。
	.word  0; -8 留下的空间，用来保护对下一个内存页的非法访问。
	__FINITDATA

bad_address:
	jmp bad_address

	.section ".init.text","ax"
#ifdef CONFIG_EARLY_PRINTK
	.globl early_idt_handlers
early_idt_handlers:
	i = 0
	.rept NUM_EXCEPTION_VECTORS
	movl $i, %esi
	jmp early_idt_handler
	i = i + 1
	.endr
#endif

ENTRY(early_idt_handler)
#ifdef CONFIG_EARLY_PRINTK
	cmpl $2,early_recursion_flag(%rip)
	jz  1f
	incl early_recursion_flag(%rip)
	GET_CR2_INTO_RCX
	movq %rcx,%r9
	xorl %r8d,%r8d		# zero for error code
	movl %esi,%ecx		# get vector number
	# Test %ecx against mask of vectors that push error code.
	cmpl $31,%ecx
	ja 0f
	movl $1,%eax
	salq %cl,%rax
	testl $0x27d00,%eax
	je 0f
	popq %r8		# get error code
0:	movq 0(%rsp),%rcx	# get ip
	movq 8(%rsp),%rdx	# get cs
	xorl %eax,%eax
	leaq early_idt_msg(%rip),%rdi
	call early_printk
	cmpl $2,early_recursion_flag(%rip)
	jz  1f
	call dump_stack
#ifdef CONFIG_KALLSYMS	
	leaq early_idt_ripmsg(%rip),%rdi
	movq 0(%rsp),%rsi	# get rip again
	call __print_symbol
#endif
#endif /* EARLY_PRINTK */
1:	hlt
	jmp 1b

#ifdef CONFIG_EARLY_PRINTK
early_recursion_flag:
	.long 0

early_idt_msg:
	.asciz "PANIC: early exception %02lx rip %lx:%lx error %lx cr2 %lx\n"
early_idt_ripmsg:
	.asciz "RIP %s\n"
#endif /* CONFIG_EARLY_PRINTK */
	.previous

; @zouyalong: 按页对齐。
#define NEXT_PAGE(name) \
	.balign	PAGE_SIZE; \
ENTRY(name)

/* Automate the creation of 1 to 1 mapping pmd entries */
#define PMDS(START, PERM, COUNT)			\
	i = 0 ;						\
	.rept (COUNT) ;					\
	.quad	(START) + (i << PMD_SHIFT) + (PERM) ;	\
	i = i + 1 ;					\
	.endr

	.data
	/*
	 * This default setting generates an ident mapping at address 0x100000
	 * and a mapping for the kernel that precisely maps virtual address
	 * 0xffffffff80000000 to physical address 0x000000. (always using
	 * 2Mbyte large pages provided by PAE mode)
	 */
NEXT_PAGE(init_level4_pgt)
	.quad	level3_ident_pgt - __START_KERNEL_map + _KERNPG_TABLE	; 第一项指向一致映射的页表项
	.org	init_level4_pgt + L4_PAGE_OFFSET*8, 0
	.quad	level3_ident_pgt - __START_KERNEL_map + _KERNPG_TABLE	; todo(@zouyalong): 这里为什么要重复一次？
	.org	init_level4_pgt + L4_START_KERNEL*8, 0
	/* (2^48-(2*1024*1024*1024))/(2^39) = 511 */
	.quad	level3_kernel_pgt - __START_KERNEL_map + _PAGE_TABLE	; __START_KERNEL_map 是内核的虚拟基地址，因此减去 __START_KERNEL_map 后就得到了 level3_kernel_pgt 的物理地址. _PAGE_TABLE 是页表项的flag。所以这里是指向了 level3_kernel_pgt 的内核页表项
	

NEXT_PAGE(level3_ident_pgt)	; 一致映射的页表项
	.quad	level2_ident_pgt - __START_KERNEL_map + _KERNPG_TABLE	; 
	.fill	511,8,0	; 剩下 511 个 8 字节的项全部填0

NEXT_PAGE(level3_kernel_pgt)
	.fill	L3_START_KERNEL,8,0
	/* (2^48-(2*1024*1024*1024)-((2^39)*511))/(2^30) = 510 */
	.quad	level2_kernel_pgt - __START_KERNEL_map + _KERNPG_TABLE
	.quad	level2_fixmap_pgt - __START_KERNEL_map + _PAGE_TABLE

NEXT_PAGE(level2_fixmap_pgt)
	.fill	506,8,0
	.quad	level1_fixmap_pgt - __START_KERNEL_map + _PAGE_TABLE
	/* 8MB reserved for vsyscalls + a 2MB hole = 4 + 1 entries */
	.fill	5,8,0

NEXT_PAGE(level1_fixmap_pgt)
	.fill	512,8,0

NEXT_PAGE(level2_ident_pgt)
	/* Since I easily can, map the first 1G.
	 * Don't set NX because code runs from these pages.
	 */
	PMDS(0, __PAGE_KERNEL_IDENT_LARGE_EXEC, PTRS_PER_PMD)

NEXT_PAGE(level2_kernel_pgt)
	/*
	 * 512 MB kernel mapping. We spend a full page on this pagetable
	 * anyway.
	 *
	 * The kernel code+data+bss must not be bigger than that.
	 *
	 * (NOTE: at +512MB starts the module area, see MODULES_VADDR.
	 *  If you want to increase this then increase MODULES_VADDR
	 *  too.)
	 */
	PMDS(0, __PAGE_KERNEL_LARGE_EXEC,
		KERNEL_IMAGE_SIZE/PMD_SIZE)

NEXT_PAGE(level2_spare_pgt)
	.fill   512, 8, 0

#undef PMDS
#undef NEXT_PAGE

	.data
	.align 16
	.globl early_gdt_descr
early_gdt_descr:
	.word	GDT_ENTRIES*8-1	; GDT_ENTRIES = 32, 全局描述符表包含了32项，用于内核代码、数据、线程局部存储段
early_gdt_descr_base:
	.quad	INIT_PER_CPU_VAR(gdt_page) ; @zouyalong gdt_page 定义在 arch/x86/include/asm/desc.h 中，此宏展开后是： init_per_cpu__gdt_page，在 linker script 中，INIT_PER_CPU 使用此变量得到新GDT的正确的基地址。

ENTRY(phys_base)
	/* This must match the first entry in level2_kernel_pgt */
	.quad   0x0000000000000000

#include "../../x86/xen/xen-head.S"
	
	.section .bss, "aw", @nobits
	.align L1_CACHE_BYTES
ENTRY(idt_table)
	.skip IDT_ENTRIES * 16

	__PAGE_ALIGNED_BSS
	.align PAGE_SIZE
ENTRY(empty_zero_page)
	.skip PAGE_SIZE
