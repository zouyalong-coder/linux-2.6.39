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
 * Select video mode
 */

#include "boot.h"
#include "video.h"
#include "vesa.h"

/// @zouyalong: 将当前屏幕上光标的位置保存起来
/// 首先函数初始化一个类型为 biosregs 的变量，将其中的 AH 寄存器内容设置成 0x3，然后调用 0x10 BIOS 中断。当中断调用返回之后，DL 和 DH 寄存器分别包含了当前光标的行和列信息。接着，这2个信息将被保存到 boot_params.screen_info 字段的 orig_x 和 orig_y字段。
static void store_cursor_position(void)
{
	struct biosregs ireg, oreg;

	initregs(&ireg);
	ireg.ah = 0x03;
	intcall(0x10, &ireg, &oreg);

	boot_params.screen_info.orig_x = oreg.dl;
	boot_params.screen_info.orig_y = oreg.dh;

	if (oreg.ch & 0x20)
		boot_params.screen_info.flags |= VIDEO_FLAGS_NOCURSOR;

	if ((oreg.ch & 0x1f) > (oreg.cl & 0x1f))
		boot_params.screen_info.flags |= VIDEO_FLAGS_NOCURSOR;
}

/// @zouyalong: 将当前使用的显示模式保存到 boot_params.screen_info.orig_video_mode。
static void store_video_mode(void)
{
	struct biosregs ireg, oreg;

	/* N.B.: the saving of the video page here is a bit silly,
	   since we pretty much assume page 0 everywhere. */
	initregs(&ireg);
	ireg.ah = 0x0f;
	intcall(0x10, &ireg, &oreg);

	/* Not all BIOSes are clean with respect to the top bit */
	boot_params.screen_info.orig_video_mode = oreg.al & 0x7f;
	boot_params.screen_info.orig_video_page = oreg.bh;
}

/*
 * Store the video mode parameters for later usage by the kernel.
 * This is done by asking the BIOS except for the rows/columns
 * parameters in the default 80x25 mode -- these are set directly,
 * because some very obscure BIOSes supply insane values.
 * @zouyalong: 将对应显示模式的相关参数写入 boot_params.screen_info 字段
 */
static void store_mode_params(void)
{
	u16 font_size;
	int x, y;

	/* For graphics mode, it is up to the mode-setting driver
	   (currently only video-vesa.c) to store the parameters */
	if (graphic_mode)
		return;

	store_cursor_position();
	store_video_mode();

	// 根据当前显示模式的设定，给 video_segment 变量设置正确的值（实际上就是设置显示内存的起始地址）。在 BIOS 将控制权转移到引导扇区的时候，显示内存地址和显示模式的对应关系如下表所示：
	// 0xB000:0x0000 	32 Kb 	Monochrome Text Video Memory
	// 0xB800:0x0000 	32 Kb 	Color Text Video Memory
	if (boot_params.screen_info.orig_video_mode == 0x07) {
		/* MDA, HGC, or VGA in monochrome mode */
		video_segment = 0xb000;
	} else {
		/* CGA, EGA, VGA and so forth */
		video_segment = 0xb800;
	}

	set_fs(0);
	// 保存字体大小信息到 boot_params.screen_info.orig_video_points：
	font_size = rdfs16(0x485); /* Font size, BIOS area */
	boot_params.screen_info.orig_video_points = font_size;

	// 从地址 0x44a 处获得屏幕列信息，从地址 0x484 处获得屏幕行信息，并将它们保存到 boot_params.screen_info.orig_video_cols 和 boot_params.screen_info.orig_video_lines
	x = rdfs16(0x44a);
	y = (adapter == ADAPTER_CGA) ? 25 : rdfs8(0x484)+1;

	if (force_x)
		x = force_x;
	if (force_y)
		y = force_y;

	boot_params.screen_info.orig_video_cols  = x;
	boot_params.screen_info.orig_video_lines = y;
}

static unsigned int get_entry(void)
{
	char entry_buf[4];
	int i, len = 0;
	int key;
	unsigned int v;

	do {
		key = getchar();

		if (key == '\b') {
			if (len > 0) {
				puts("\b \b");
				len--;
			}
		} else if ((key >= '0' && key <= '9') ||
			   (key >= 'A' && key <= 'Z') ||
			   (key >= 'a' && key <= 'z')) {
			if (len < sizeof entry_buf) {
				entry_buf[len++] = key;
				putchar(key);
			}
		}
	} while (key != '\r');
	putchar('\n');

	if (len == 0)
		return VIDEO_CURRENT_MODE; /* Default */

	v = 0;
	for (i = 0; i < len; i++) {
		v <<= 4;
		key = entry_buf[i] | 0x20;
		v += (key > '9') ? key-'a'+10 : key-'0';
	}

	return v;
}

static void display_menu(void)
{
	struct card_info *card;
	struct mode_info *mi;
	char ch;
	int i;
	int nmodes;
	int modes_per_line;
	int col;

	nmodes = 0;
	for (card = video_cards; card < video_cards_end; card++)
		nmodes += card->nmodes;

	modes_per_line = 1;
	if (nmodes >= 20)
		modes_per_line = 3;

	for (col = 0; col < modes_per_line; col++)
		puts("Mode: Resolution:  Type: ");
	putchar('\n');

	col = 0;
	ch = '0';
	for (card = video_cards; card < video_cards_end; card++) {
		mi = card->modes;
		for (i = 0; i < card->nmodes; i++, mi++) {
			char resbuf[32];
			int visible = mi->x && mi->y;
			u16 mode_id = mi->mode ? mi->mode :
				(mi->y << 8)+mi->x;

			if (!visible)
				continue; /* Hidden mode */

			if (mi->depth)
				sprintf(resbuf, "%dx%d", mi->y, mi->depth);
			else
				sprintf(resbuf, "%d", mi->y);

			printf("%c %03X %4dx%-7s %-6s",
			       ch, mode_id, mi->x, resbuf, card->card_name);
			col++;
			if (col >= modes_per_line) {
				putchar('\n');
				col = 0;
			}

			if (ch == '9')
				ch = 'a';
			else if (ch == 'z' || ch == ' ')
				ch = ' '; /* Out of keys... */
			else
				ch++;
		}
	}
	if (col)
		putchar('\n');
}

#define H(x)	((x)-'a'+10)
#define SCAN	((H('s')<<12)+(H('c')<<8)+(H('a')<<4)+H('n'))

static unsigned int mode_menu(void)
{
	int key;
	unsigned int sel;

	puts("Press <ENTER> to see video modes available, "
	     "<SPACE> to continue, or wait 30 sec\n");

	kbd_flush();
	while (1) {
		key = getchar_timeout();
		if (key == ' ' || key == 0)
			return VIDEO_CURRENT_MODE; /* Default */
		if (key == '\r')
			break;
		putchar('\a');	/* Beep! */
	}


	for (;;) {
		display_menu();

		puts("Enter a video mode or \"scan\" to scan for "
		     "additional modes: ");
		sel = get_entry();
		if (sel != SCAN)
			return sel;

		probe_cards(1);
	}
}

/* Save screen content to the heap */
static struct saved_screen {
	int x, y;
	int curx, cury;
	u16 *data;
} saved;

/// @zouyalong: 获得当前屏幕的所有信息（包括屏幕大小，当前光标位置，屏幕上的字符信息），并且保存到 saved_screen 结构体中
static void save_screen(void)
{
	/* Should be called after store_mode_params() */
	saved.x = boot_params.screen_info.orig_video_cols;
	saved.y = boot_params.screen_info.orig_video_lines;
	saved.curx = boot_params.screen_info.orig_x;
	saved.cury = boot_params.screen_info.orig_y;

	if (!heap_free(saved.x*saved.y*sizeof(u16)+512))
		return;		/* Not enough heap to save the screen */

	saved.data = GET_HEAP(u16, saved.x*saved.y);

	set_fs(video_segment);
	copy_from_fs(saved.data, 0, saved.x*saved.y*sizeof(u16));
}

static void restore_screen(void)
{
	/* Should be called after store_mode_params() */
	int xs = boot_params.screen_info.orig_video_cols;
	int ys = boot_params.screen_info.orig_video_lines;
	int y;
	addr_t dst = 0;
	u16 *src = saved.data;
	struct biosregs ireg;

	if (graphic_mode)
		return;		/* Can't restore onto a graphic mode */

	if (!src)
		return;		/* No saved screen contents */

	/* Restore screen contents */

	set_fs(video_segment);
	for (y = 0; y < ys; y++) {
		int npad;

		if (y < saved.y) {
			int copy = (xs < saved.x) ? xs : saved.x;
			copy_to_fs(dst, src, copy*sizeof(u16));
			dst += copy*sizeof(u16);
			src += saved.x;
			npad = (xs < saved.x) ? 0 : xs-saved.x;
		} else {
			npad = xs;
		}

		/* Writes "npad" blank characters to
		   video_segment:dst and advances dst */
		asm volatile("pushw %%es ; "
			     "movw %2,%%es ; "
			     "shrw %%cx ; "
			     "jnc 1f ; "
			     "stosw \n\t"
			     "1: rep;stosl ; "
			     "popw %%es"
			     : "+D" (dst), "+c" (npad)
			     : "bdS" (video_segment),
			       "a" (0x07200720));
	}

	/* Restore cursor position */
	if (saved.curx >= xs)
		saved.curx = xs-1;
	if (saved.cury >= ys)
		saved.cury = ys-1;

	initregs(&ireg);
	ireg.ah = 0x02;		/* Set cursor position */
	ireg.dh = saved.cury;
	ireg.dl = saved.curx;
	intcall(0x10, &ireg, NULL);

	store_cursor_position();
}

/// @zouyalong: 显示模式初始化。通过用户菜单选择显示模式，然后调用set_mode()函数设置显示模式。
/// @param  
void set_video(void)
{
	u16 mode = boot_params.hdr.vid_mode;

	RESET_HEAP();

	store_mode_params();
	// @zouyalong: 将当前屏幕上的所有信息保存到 HEAP 中。
	save_screen();
	// 遍历显卡。
	probe_cards(0);

	for (;;) {
		if (mode == ASK_VGA)
			mode = mode_menu();

		if (!set_mode(mode))
			break;

		printf("Undefined video mode number: %x\n", mode);
		mode = ASK_VGA;
	}
	boot_params.hdr.vid_mode = mode;
	vesa_store_edid();
	store_mode_params();

	if (do_restore)
		restore_screen();
}
