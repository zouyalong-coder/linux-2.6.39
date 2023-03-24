#ifndef _ASM_X86_PAGE_64_DEFS_H
#define _ASM_X86_PAGE_64_DEFS_H

#define THREAD_ORDER	1
// @zouyalong: 线程栈大小
#define THREAD_SIZE  (PAGE_SIZE << THREAD_ORDER) // 2 * 4096 = 8192 8K
#define CURRENT_MASK (~(THREAD_SIZE - 1))

#define EXCEPTION_STACK_ORDER 0
#define EXCEPTION_STKSZ (PAGE_SIZE << EXCEPTION_STACK_ORDER)

#define DEBUG_STACK_ORDER (EXCEPTION_STACK_ORDER + 1)
#define DEBUG_STKSZ (PAGE_SIZE << DEBUG_STACK_ORDER)

#define IRQ_STACK_ORDER 2
#define IRQ_STACK_SIZE (PAGE_SIZE << IRQ_STACK_ORDER)

#define STACKFAULT_STACK 1
#define DOUBLEFAULT_STACK 2
#define NMI_STACK 3
#define DEBUG_STACK 4
#define MCE_STACK 5
#define N_EXCEPTION_STACKS 5  /* hw limit: 7 */

#define PUD_PAGE_SIZE		(_AC(1, UL) << PUD_SHIFT)
#define PUD_PAGE_MASK		(~(PUD_PAGE_SIZE-1))

/**
 * @zouyalong: 0xffff880000000000UL
 * Set __PAGE_OFFSET to the most negative possible address +
 * PGDIR_SIZE*16 (pgd slot 272).  The gap is to allow a space for a
 * hypervisor to fit.  Choosing 16 slots here is arbitrary, but it's
 * what Xen requires.
 */
#define __PAGE_OFFSET           _AC(0xffff880000000000, UL)

#define __PHYSICAL_START	((CONFIG_PHYSICAL_START +	 	\
				  (CONFIG_PHYSICAL_ALIGN - 1)) &	\
				 ~(CONFIG_PHYSICAL_ALIGN - 1))

/**
 * @zouyalong:
 * 默认：
 * Linux 内核的物理基址 - 0x1000000;
 * Linux 内核的虚拟基址 - 0xffffffff81000000 
 */
#define __START_KERNEL		(__START_KERNEL_map + __PHYSICAL_START)
// @zouyalong: 内核虚拟基地址
#define __START_KERNEL_map	_AC(0xffffffff80000000, UL)

/* See Documentation/x86/x86_64/mm.txt for a description of the memory map. */
#define __PHYSICAL_MASK_SHIFT	46
#define __VIRTUAL_MASK_SHIFT	47

/*
 * Kernel image size is limited to 512 MB (see level2_kernel_pgt in
 * arch/x86/kernel/head_64.S), and it is mapped here:
 */
#define KERNEL_IMAGE_SIZE	(512 * 1024 * 1024)
#define KERNEL_IMAGE_START	_AC(0xffffffff80000000, UL)

#ifndef __ASSEMBLY__
void clear_page(void *page);
void copy_page(void *to, void *from);

/* duplicated to the one in bootmem.h */
extern unsigned long max_pfn;
extern unsigned long phys_base;

extern unsigned long __phys_addr(unsigned long);
#define __phys_reloc_hide(x)	(x)

#define vmemmap ((struct page *)VMEMMAP_START)

extern void init_extra_mapping_uc(unsigned long phys, unsigned long size);
extern void init_extra_mapping_wb(unsigned long phys, unsigned long size);

#endif	/* !__ASSEMBLY__ */

#ifdef CONFIG_FLATMEM
#define pfn_valid(pfn)          ((pfn) < max_pfn)
#endif

#endif /* _ASM_X86_PAGE_64_DEFS_H */
