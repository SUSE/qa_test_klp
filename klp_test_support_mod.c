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
#include <linux/kprobes.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
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


static LIST_HEAD(active_probes);
static DEFINE_MUTEX(active_probes_mutex);

struct active_probe
{
	enum active_probe_type
	{
		apt_kprobe,
		apt_jprobe,
		apt_kretprobe,
	} type;

	struct list_head list;

	union
	{
		struct kprobe kp;
		struct jprobe jp;
		struct kretprobe rp;
	} p;
};

static inline struct kprobe *active_probe_kprobe(struct active_probe *a)
{
	switch (a->type) {
	case apt_kprobe:
		return &a->p.kp;

	case apt_jprobe:
		return &a->p.jp.kp;

	case apt_kretprobe:
		return &a->p.rp.kp;
	};

	return NULL;
}

static inline const char *active_probe_symbol_name(struct active_probe *a)
{
	return active_probe_kprobe(a)->symbol_name;
}

static struct active_probe *alloc_active_probe(const char *symbol_name,
					       enum active_probe_type type)
{
	struct active_probe *a;
	const char *s;

	a = kzalloc(sizeof(*a), GFP_KERNEL);
	if (!a)
		return NULL;

	s = kstrdup(symbol_name, GFP_KERNEL);
	if (!s) {
		kfree(a);
		return NULL;
	}

	switch (type) {
	case apt_kprobe:
		a->p.kp.symbol_name = s;
		break;

	case apt_jprobe:
		a->p.jp.kp.symbol_name = s;
		break;

	case apt_kretprobe:
		a->p.rp.kp.symbol_name = s;
		break;
	};

	a->type = type;
	return a;
}

static void free_active_probe(struct active_probe *a)
{
	kfree((void *)active_probe_symbol_name(a));
	kfree(a);
}

static void __remove_probe(struct active_probe *a)
{
	switch (a->type) {
	case apt_kprobe:
		unregister_kprobe(&a->p.kp);
		break;

	case apt_jprobe:
		unregister_jprobe(&a->p.jp);
		break;

	case apt_kretprobe:
		unregister_kretprobe(&a->p.rp);
		break;
	};

	list_del(&a->list);
	free_active_probe(a);
}

static void do_remove_probes(const char *symbol)
{
	struct active_probe *a, *tmp;

	mutex_lock(&active_probes_mutex);
	list_for_each_entry_safe(a, tmp, &active_probes, list) {
		if (strcmp(symbol, active_probe_symbol_name(a)))
			continue;

		__remove_probe(a);
	}
	mutex_unlock(&active_probes_mutex);
}

static ssize_t remove_probes_write(struct file *file, const char __user *buf,
				   size_t len, loff_t *ppos)
{
	char *s;

	s = kmalloc(len + 1, GFP_KERNEL);
	if (!s)
		return -ENOMEM;

	if (copy_from_user(s, buf, len)) {
		kfree(s);
		return -EFAULT;
	}
	s[len] = '\0';

	do_remove_probes(s);

	kfree(s);
	return len;
}

static const struct file_operations fops_remove_probes = {
	.owner = THIS_MODULE,
	.open = nonseekable_open,
	.write = remove_probes_write,
	.llseek = no_llseek,
};

static int kp_pre_handler(struct kprobe *kp, struct pt_regs *regs)
{
	return 0;
}

static void kp_post_handler(struct kprobe *kp, struct pt_regs *regs,
			    unsigned long flags)
{
	return;
}

static int do_add_kprobe(const char *symbol_name)
{
	struct active_probe *a;
	int r;

	a = alloc_active_probe(symbol_name, apt_kprobe);
	if (!a)
		return -ENOMEM;

	a->p.kp.pre_handler = kp_pre_handler;
	a->p.kp.post_handler = kp_post_handler;

	r = register_kprobe(&a->p.kp);
	if (!r) {
		mutex_lock(&active_probes_mutex);
		list_add_tail(&a->list, &active_probes);
		mutex_unlock(&active_probes_mutex);
	} else {
		free_active_probe(a);
	}

	return r;
}

static ssize_t add_kprobe_write(struct file *file, const char __user *buf,
				size_t len, loff_t *ppos)
{
	int ret;
	char *s;

	s = kmalloc(len + 1, GFP_KERNEL);
	if (!s)
		return -ENOMEM;

	if (copy_from_user(s, buf, len)) {
		kfree(s);
		return -EFAULT;
	}
	s[len] = '\0';

	ret = do_add_kprobe(s);

	kfree(s);
	return ret ? ret : len;
}

static const struct file_operations fops_add_kprobe = {
	.owner = THIS_MODULE,
	.open = nonseekable_open,
	.write = add_kprobe_write,
	.llseek = no_llseek,
};

static void jp_handler(void)
{
	jprobe_return();
}

static int do_add_jprobe(const char *symbol_name)
{
	struct active_probe *a;
	int r;

	a = alloc_active_probe(symbol_name, apt_jprobe);
	if (!a)
		return -ENOMEM;

	a->p.jp.entry = jp_handler;

	r = register_jprobe(&a->p.jp);
	if (!r) {
		mutex_lock(&active_probes_mutex);
		list_add_tail(&a->list, &active_probes);
		mutex_unlock(&active_probes_mutex);
	} else {
		free_active_probe(a);
	}

	return r;
}

static ssize_t add_jprobe_write(struct file *file, const char __user *buf,
				size_t len, loff_t *ppos)
{
	int ret;
	char *s;

	s = kmalloc(len + 1, GFP_KERNEL);
	if (!s)
		return -ENOMEM;

	if (copy_from_user(s, buf, len)) {
		kfree(s);
		return -EFAULT;
	}
	s[len] = '\0';

	ret = do_add_jprobe(s);

	kfree(s);
	return ret ? ret : len;
}

static const struct file_operations fops_add_jprobe = {
	.owner = THIS_MODULE,
	.open = nonseekable_open,
	.write = add_jprobe_write,
	.llseek = no_llseek,
};

static int rp_handler(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	return 0;
}

static int do_add_kretprobe(const char *symbol_name)
{
	struct active_probe *a;
	int r;

	a = alloc_active_probe(symbol_name, apt_kretprobe);
	if (!a)
		return -ENOMEM;

	a->p.rp.handler = rp_handler;
	a->p.rp.entry_handler = rp_handler;

	r = register_kretprobe(&a->p.rp);
	if (!r) {
		mutex_lock(&active_probes_mutex);
		list_add_tail(&a->list, &active_probes);
		mutex_unlock(&active_probes_mutex);
	} else {
		free_active_probe(a);
	}

	return r;
}

static ssize_t add_kretprobe_write(struct file *file, const char __user *buf,
				   size_t len, loff_t *ppos)
{
	int ret;
	char *s;

	s = kmalloc(len + 1, GFP_KERNEL);
	if (!s)
		return -ENOMEM;

	if (copy_from_user(s, buf, len)) {
		kfree(s);
		return -EFAULT;
	}
	s[len] = '\0';

	ret = do_add_kretprobe(s);

	kfree(s);
	return ret ? ret : len;
}

static const struct file_operations fops_add_kretprobe = {
	.owner = THIS_MODULE,
	.open = nonseekable_open,
	.write = add_kretprobe_write,
	.llseek = no_llseek,
};


static int active_probes_show(struct seq_file *s, void *p)
{
	struct active_probe *a;
	const char *type = NULL;

	mutex_lock(&active_probes_mutex);
	list_for_each_entry(a, &active_probes, list) {
		switch (a->type) {
		case apt_kprobe:
			type = "kprobe";
			break;

		case apt_jprobe:
			type = "jprobe";
			break;

		case apt_kretprobe:
			type = "kretprobe";
			break;
		};

		seq_printf(s, "%s [%s]\n", active_probe_symbol_name(a), type);

	}
	mutex_unlock(&active_probes_mutex);
	return 0;
}

static int active_probes_open(struct inode *inode, struct file *f)
{
	return single_open(f, active_probes_show, NULL);
}

static const struct file_operations fops_active_probes = {
	.owner = THIS_MODULE,
	.open = active_probes_open,
	.release = single_release,
	.read = seq_read,
	.llseek = seq_lseek,
};


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

	d = debugfs_create_file_unsafe("remove_probes",
				       S_IWUSR, debugfs_dir, NULL,
				       &fops_remove_probes);
	if (IS_ERR(d))
		goto err;

	d = debugfs_create_file_unsafe("add_kprobe",
				       S_IWUSR, debugfs_dir, NULL,
				       &fops_add_kprobe);
	if (IS_ERR(d))
		goto err;

	d = debugfs_create_file_unsafe("add_jprobe",
				       S_IWUSR, debugfs_dir, NULL,
				       &fops_add_jprobe);
	if (IS_ERR(d))
		goto err;

	d = debugfs_create_file_unsafe("add_kretprobe",
				       S_IWUSR, debugfs_dir, NULL,
				       &fops_add_kretprobe);
	if (IS_ERR(d))
		goto err;

	d = debugfs_create_file_unsafe("active_probes",
				       S_IRUSR, debugfs_dir, NULL,
				       &fops_active_probes);
	if (IS_ERR(d))
		goto err;

	return 0;

err:
	debugfs_remove_recursive(debugfs_dir);
	return PTR_ERR(d);
}

static void test_support_mod_exit(void)
{
	struct active_probe *a, *tmp;

	debugfs_remove_recursive(debugfs_dir);

	list_for_each_entry_safe(a, tmp, &active_probes, list) {
		__remove_probe(a);
	}
}

module_init(test_support_mod_init);
module_exit(test_support_mod_exit);
MODULE_LICENSE("GPL");
