#ifndef _ASM_X86_BIOS_EBDA_H
#define _ASM_X86_BIOS_EBDA_H

#include <asm/io.h>

/*
 * there is a real-mode segmented pointer pointing to the
 * 4K EBDA area at 0x40E.
 */
// @zouyalong: 将物理地址 0x40E 转换为虚拟地址，0x0040:0x000e 就是包含有扩展BIOS数据区域基地址的代码段。
static inline unsigned int get_bios_ebda(void)
{
	unsigned int address = *(unsigned short *)phys_to_virt(0x40E);
	address <<= 4;
	return address;	/* 0 means none */
}

void reserve_ebda_region(void);

#ifdef CONFIG_X86_CHECK_BIOS_CORRUPTION
/*
 * This is obviously not a great place for this, but we want to be
 * able to scatter it around anywhere in the kernel.
 */
void check_for_bios_corruption(void);
void start_periodic_check_for_corruption(void);
#else
static inline void check_for_bios_corruption(void)
{
}

static inline void start_periodic_check_for_corruption(void)
{
}
#endif

#endif /* _ASM_X86_BIOS_EBDA_H */
