/* Written 2000 by Andi Kleen */
#ifndef _ASM_X86_DESC_DEFS_H
#define _ASM_X86_DESC_DEFS_H

/*
 * Segment descriptor structure definitions, usable from both x86_64 and i386
 * archs.
 */

#ifndef __ASSEMBLY__

#include <linux/types.h>

/*
 * FIXME: Accessing the desc_struct through its fields is more elegant,
 * and should be the one valid thing to do. However, a lot of open code
 * still touches the a and b accessors, and doing this allow us to do it
 * incrementally. We keep the signature as a struct, rather than an union,
 * so we can get rid of it transparently in the future -- glommer
 */
/* 8 byte segment descriptor */
/**
 * @zouyalong: 8 字节的段描述符。在 GDT 中，一个是 tss、另一个是 ldt 
 * 
 */
struct desc_struct {
	union {
		struct {
			unsigned int a;
			unsigned int b;
		};
		struct {
			u16 limit0;
			u16 base0;
			unsigned base1: 8, type: 4, s: 1, dpl: 2, p: 1;
			unsigned limit: 4, avl: 1, l: 1, d: 1, g: 1, base2: 8;
		};
	};
} __attribute__((packed));

#define GDT_ENTRY_INIT(flags, base, limit) { { { \
		.a = ((limit) & 0xffff) | (((base) & 0xffff) << 16), \
		.b = (((base) & 0xff0000) >> 16) | (((flags) & 0xf0ff) << 8) | \
			((limit) & 0xf0000) | ((base) & 0xff000000), \
	} } }

/// @zouyalong: 中断类型。
enum {
	GATE_INTERRUPT = 0xE,	// @zouyalong: 中断门
	GATE_TRAP = 0xF,	// @zouyalong: 陷阱门
	GATE_CALL = 0xC,	// @zouyalong: 调用门
	GATE_TASK = 0x5,	// @zouyalong: 任务门
};

/* 16byte gate */
/**
 * @zouyalong: 中断门（中断向量表中的项）。64位系统中是 16 字节的。在 32 位系统中是 8 字节的。结构如下：
127                                                                             96
 --------------------------------------------------------------------------------
|                                                                               |
|                                Reserved                                       |
|                                                                               |
 --------------------------------------------------------------------------------
95                                                                              64
 --------------------------------------------------------------------------------
|                                                                               |
|                               Offset 63..32                                   |
|                                                                               |
 --------------------------------------------------------------------------------
63                               48 47      46  44   42    39             34    32
 --------------------------------------------------------------------------------
|                                  |       |  D  |   |     |      |   |   |     |
|       Offset 31..16              |   P   |  P  | 0 |Type |0 0 0 | 0 | 0 | IST |
|                                  |       |  L  |   |     |      |   |   |     |
 --------------------------------------------------------------------------------
31                                   15 16                                      0
 --------------------------------------------------------------------------------
|                                      |                                        |
|          Segment Selector            |                 Offset 15..0           |
|                                      |                                        |
 --------------------------------------------------------------------------------
Offset - 代表了到中断处理程序入口点的偏移；
DPL - 描述符特权级别；
P - Segment Present 标志;
Segment selector - 在GDT或LDT中的代码段选择子；
IST - 用来为中断处理提供一个新的栈。
 */
struct gate_struct64 {
	u16 offset_low;
	u16 segment;
	unsigned ist : 3, // interrupt stack table, 用来为中断处理提供一个新的栈。这个栈是在 TSS 中的。当中断发生时，硬件加载这个描述符，然后硬件根据 IST 的值自动设置新的栈指针。 之后激活对应的中断处理函数。所有的特殊内核栈会在 cpu_init 函数中设置好
		zero0 : 5,	// reserved
		type : 5,	// 0xe for interrupt gate, 0xf for trap gate， 0xc for call gate。中断门、陷阱门、调用门。中断和陷入的区别是 CPU 的IF标志位，中断门会自动将IF置为1（不可被再次中断），而陷阱门不会。iret 指令会将IF置为1。
		dpl : 2,	// descriptor privilege level
		p : 1;	// present	
	u16 offset_middle;
	u32 offset_high;
	u32 zero1;
} __attribute__((packed));

#define PTR_LOW(x) ((unsigned long long)(x) & 0xFFFF)
#define PTR_MIDDLE(x) (((unsigned long long)(x) >> 16) & 0xFFFF)
#define PTR_HIGH(x) ((unsigned long long)(x) >> 32)

enum {
	DESC_TSS = 0x9,
	DESC_LDT = 0x2,
	DESCTYPE_S = 0x10,	/* !system */
};

/* LDT or TSS descriptor in the GDT. 16 bytes. */
struct ldttss_desc64 {
	u16 limit0;
	u16 base0;
	unsigned base1 : 8, type : 5, dpl : 2, p : 1;
	unsigned limit1 : 4, zero0 : 3, g : 1, base2 : 8;
	u32 base3;
	u32 zero1;
} __attribute__((packed));

#ifdef CONFIG_X86_64
typedef struct gate_struct64 gate_desc;
typedef struct ldttss_desc64 ldt_desc;
typedef struct ldttss_desc64 tss_desc;
#define gate_offset(g) ((g).offset_low | ((unsigned long)(g).offset_middle << 16) | ((unsigned long)(g).offset_high << 32))
#define gate_segment(g) ((g).segment)
#else
typedef struct desc_struct gate_desc;
typedef struct desc_struct ldt_desc;
typedef struct desc_struct tss_desc;
#define gate_offset(g)		(((g).b & 0xffff0000) | ((g).a & 0x0000ffff))
#define gate_segment(g)		((g).a >> 16)
#endif

/// @zouyalong: gdt/idt的描述符. packed 表示紧凑型排列，不做对齐优化。即此结构体的字节数为 16 + 32 = 48 字节。
/// 参考：https://wiki.osdev.org/Global_Descriptor_Table
struct desc_ptr {
	unsigned short size;
	unsigned long address;
} __attribute__((packed)) ; 

#endif /* !__ASSEMBLY__ */

#endif /* _ASM_X86_DESC_DEFS_H */
