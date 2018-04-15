/*
 * klp_test_support_mod - support module for KLP testing
 *
 *  Copyright (c) 2018 SUSE
 *   Author: Nicolai Stange
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 */

#include <linux/module.h>
#include <linux/debugfs.h>
#include "klp_test_support_mod.h"

#if !IS_ENABLED(CONFIG_DEBUG_FS)
#error "Test support module requires CONFIG_DEBUG_FS=y."
#endif

static const struct file_operations fops_active_livepatch_id = {
	.owner = THIS_MODULE,
	.read = orig_active_livepatch_id_read,
	.open = simple_open,
	.llseek = default_llseek,
};

DEFINE_DEBUGFS_ATTRIBUTE(fops_sleep_interruptible,
			 NULL, orig_sleep_interruptible_set, "%llu\n");

DEFINE_DEBUGFS_ATTRIBUTE(fops_sleep_uninterruptible,
			 NULL, orig_sleep_uninterruptible_set, "%llu\n");

DEFINE_DEBUGFS_ATTRIBUTE(fops_hog_cpu_interruptible,
			 NULL, orig_hog_cpu_interruptible_set, "%llu\n");

DEFINE_DEBUGFS_ATTRIBUTE(fops_hog_cpu_uninterruptible,
			 NULL, orig_hog_cpu_uninterruptible_set, "%llu\n");


static struct dentry *debugfs_dir;

static int test_support_mod_init(void)
{
	struct dentry *d;
	debugfs_dir = debugfs_create_dir("klp_test_support", NULL);
	if (IS_ERR(debugfs_dir))
		return PTR_ERR(debugfs_dir);

	d = debugfs_create_file_unsafe("active_livepatch_id",
				       S_IRUSR | S_IRGRP | S_IROTH,
				       debugfs_dir, NULL,
				       &fops_active_livepatch_id);
	if (IS_ERR(d))
		goto err;

	d = debugfs_create_file_unsafe("sleep_interruptible",
				       S_IWUSR, debugfs_dir, NULL,
				       &fops_sleep_interruptible);
	if (IS_ERR(d))
		goto err;

	d = debugfs_create_file_unsafe("sleep_uninterruptible",
				       S_IWUSR, debugfs_dir, NULL,
				       &fops_sleep_uninterruptible);
	if (IS_ERR(d))
		goto err;

	d = debugfs_create_file_unsafe("hog_cpu_interruptible",
				       S_IWUSR, debugfs_dir, NULL,
				       &fops_hog_cpu_interruptible);
	if (IS_ERR(d))
		goto err;

	d = debugfs_create_file_unsafe("hog_cpu_uninterruptible",
				       S_IWUSR, debugfs_dir, NULL,
				       &fops_hog_cpu_uninterruptible);
	if (IS_ERR(d))
		goto err;

	return 0;

err:
	debugfs_remove_recursive(debugfs_dir);
	return PTR_ERR(d);
}

static void test_support_mod_exit(void)
{
	debugfs_remove_recursive(debugfs_dir);
}

module_init(test_support_mod_init);
module_exit(test_support_mod_exit);
MODULE_LICENSE("GPL");
