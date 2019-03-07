/*
 * klp_test_livepatch - test livepatch template
 *
 *  Copyright (c) 2017-2018 SUSE
 *   Authors: Libor Pechacek, Nicolai Stange
 */

/*
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/livepatch.h>

#define PATCH_ID @@PATCH_ID@@

#include "klp_test_support_mod.h"

/* whether or not to identity-patch sys_getpid() */
#define PATCH_GETPID @@PATCH_GETPID@@

#if PATCH_GETPID
asmlinkage long PATCHED_SYM(sys_getpid)(void)
{
	return task_tgid_vnr(current);
}

static struct klp_func vmlinux_funcs[] = {
	{
		.old_name = "sys_getpid",
		.new_func = PATCHED_SYM(sys_getpid),
	},
	{}
};
#endif /* PATCH_GETPID */

static struct klp_func klp_test_support_mod_funcs[] = {
	@@PATCH_FUNCS@@
	{}
};

static struct klp_object objs[] = {
#if PATCH_GETPID
	{
		/* name being NULL means vmlinux */
		.funcs = vmlinux_funcs,
	},
#endif /* PATCH_GETPID */
	{
		.name = "klp_test_support_mod",
		.funcs = klp_test_support_mod_funcs,
	},
	{}
};

static struct klp_patch patch = {
	.mod = THIS_MODULE,
	.objs = objs,
	.replace = @@PATCH_REPLACE_ALL@@,
};


static int livepatch_init(void)
{
#ifndef KLP_NOREG_API
	int ret;

	ret = klp_register_patch(&patch);
	if (ret)
		return ret;
	ret = klp_enable_patch(&patch);
	if (ret) {
		WARN_ON(klp_unregister_patch(&patch));
		return ret;
	}
	return 0;
#else
	return klp_enable_patch(&patch);
#endif
}

static void livepatch_exit(void)
{
#ifndef KLP_NOREG_API
	WARN_ON(klp_unregister_patch(&patch));
#endif
}

module_init(livepatch_init);
module_exit(livepatch_exit);
MODULE_LICENSE("GPL");
MODULE_INFO(livepatch, "Y");
