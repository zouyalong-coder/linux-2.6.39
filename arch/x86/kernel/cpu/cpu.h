#ifndef ARCH_X86_CPU_H

#define ARCH_X86_CPU_H

struct cpu_model_info {
	int		vendor;
	int		family;
	const char	*model_names[16];
};

// zouyalong: cpu_dev 结构体。用于描述 cpu 的属性。attempt to consolidate cpu attributes
struct cpu_dev {
	const char	*c_vendor;	// @zouyalong: cpu 厂商

	/* some have two possibilities for cpuid string */
	const char	*c_ident[2];	// @zouyalong: cpu 的标识符

	struct		cpu_model_info c_models[4];	// @zouyalong: cpu 的型号

	void            (*c_early_init)(struct cpuinfo_x86 *);
	void		(*c_init)(struct cpuinfo_x86 *);
	void		(*c_identify)(struct cpuinfo_x86 *);
	unsigned int	(*c_size_cache)(struct cpuinfo_x86 *, unsigned int);
	int		c_x86_vendor;
};

#define cpu_dev_register(cpu_devX) \
	static const struct cpu_dev *const __cpu_dev_##cpu_devX __used \
	__attribute__((__section__(".x86_cpu_dev.init"))) = \
	&cpu_devX;

// @zouyalong: 在 linker 中定义，描述 cpu_dev 数组
extern const struct cpu_dev *const __x86_cpu_dev_start[],
			    *const __x86_cpu_dev_end[];

extern void get_cpu_cap(struct cpuinfo_x86 *c);
extern void cpu_detect_cache_sizes(struct cpuinfo_x86 *c);
extern void get_cpu_cap(struct cpuinfo_x86 *c);

#endif
