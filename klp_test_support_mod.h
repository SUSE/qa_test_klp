/*
 * klp_test_support_mod - support module for KLP testing
 *
 *  Copyright (c) 2018-2019 SUSE
 *   Author: Nicolai Stange
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 */

#ifndef _KLP_TEST_SUPPORT_MOD_H
#define _KLP_TEST_SUPPORT_MOD_H

#include <linux/compiler.h>
#include <linux/hrtimer.h>
#include <linux/sched.h>
#include <linux/signal.h>
#include <linux/debugfs.h>
#include <asm/uaccess.h>

#define USE_OLD_HRTIMER_API @@USE_OLD_HRTIMER_API@@

#if defined(PATCH_ID)
#define __PATCHED_SYM(id, sym) klp_ ## id ## _ ## sym
#define _PATCHED_SYM(id, sym) __PATCHED_SYM(id, sym)
#define PATCHED_SYM(sym) _PATCHED_SYM(PATCH_ID, sym)
#else
#define PATCHED_SYM(sym) orig_ ## sym
#endif


#if defined(PATCH_ID)
static const char livepatch_id[] = __stringify(PATCH_ID) "\n";
#else
static const char livepatch_id[] = "none\n";
#endif

static noinline __maybe_unused
void PATCHED_SYM(__make_stackframe_valid)(void)
{
	static volatile int dummy;
	/* Prevent us from getting optimized away */
	asm volatile ("" : "=r" (dummy));
}

static noinline __maybe_unused
void PATCHED_SYM(make_stackframe_valid)(void)
{
	/*
	 * Make sure that the calling function's stackframe gets
	 * filled in on ppc64le. This is necessary for the reliable
	 * stacktrace implementation not to mark it as unreliable.
	 */
	static volatile int dummy;

	/*
	 * Call another dummy in order to make the compiler fill in
	 * the parent's stackframe
	 */
	PATCHED_SYM(__make_stackframe_valid)();
	/*
	 * Prevent us from getting optimized away. Must come after
	 * the function call to prevent tail optimization.
	 */
	asm volatile ("" : "=r" (dummy));
}

static noinline __maybe_unused
const size_t PATCHED_SYM(do_read_active_livepatch_id)(char __user *to,
						      loff_t pos,
						      size_t count)
{
	/*
	 * This is an inefficient implementation of copy_to_user().
	 * The goal is to have the memory stores inlined such that
	 * fault exceptions happen here.
	 */
	while (count) {
		if (put_user(livepatch_id[pos], to))
			return count;
		--count;
		++pos;
		++to;
	}

	return 0;
}

static noinline __maybe_unused
ssize_t PATCHED_SYM(active_livepatch_id_read)(struct file *file,
					      char __user *user_buf,
					      size_t count,
					      loff_t *ppos)
{
	/*
	 * This is basically simple_read_from_buffer() open coded:
	 * instead of copy_to_user(), it invokeds
	 * do_get_active_livepatch_id().
	 */
	loff_t pos = *ppos;
	size_t ret;

	/* Make this function's stack frame valid on ppc64le. */
	PATCHED_SYM(make_stackframe_valid)();

	if (pos < 0)
		return -EINVAL;
	if (pos >= sizeof(livepatch_id) || !count)
		return 0;
	if (count > sizeof(livepatch_id) - pos)
		count = sizeof(livepatch_id) - pos;
	ret = PATCHED_SYM(do_read_active_livepatch_id)(user_buf, pos, count);
	if (ret == count)
		return -EFAULT;
	count -= ret;
	*ppos = pos + count;
	return count;
}

static noinline __maybe_unused
int PATCHED_SYM(do_sleep)(unsigned long secs, int task_state)
{
	struct hrtimer_sleeper t;

	/* code duplication is intentional for the sake of limiting the number
	 * of #ifdef's */
#if USE_OLD_HRTIMER_API
	hrtimer_init_on_stack(&t.timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
	hrtimer_set_expires_range_ns(&t.timer, ktime_set(secs, 0), 0);
	hrtimer_init_sleeper(&t, current);
#else
	hrtimer_init_sleeper_on_stack(&t, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
	hrtimer_set_expires_range_ns(&t.timer, ktime_set(secs, 0), 0);
#endif

	set_current_state(task_state);
	hrtimer_start_expires(&t.timer, HRTIMER_MODE_REL);

	if (likely(t.task))
		schedule();

	hrtimer_cancel(&t.timer);
	__set_current_state(TASK_RUNNING);

	/*
	 * If the timer expired, t->task will be set to NULL.
	 * Otherwise a signal will be pending.
	 */
	return !!t.task;
}

static noinline __maybe_unused
int PATCHED_SYM(sleep_interruptible_set)(void *data, u64 val)
{
	PATCHED_SYM(do_sleep)((unsigned long)val, TASK_INTERRUPTIBLE);
	return 0;
}

static noinline __maybe_unused
int PATCHED_SYM(sleep_uninterruptible_set)(void *data, u64 val)
{
	PATCHED_SYM(do_sleep)((unsigned long)val, TASK_UNINTERRUPTIBLE);
	return 0;
}


static noinline __maybe_unused
int PATCHED_SYM(do_hog_cpu)(unsigned long secs, bool interruptible)
{
	const ktime_t end = ktime_add(ktime_get(), ktime_set(secs, 0));

	while (ktime_compare(ktime_get(), end) < 0) {
		if (interruptible && signal_pending(current))
			return 1;
		cond_resched();
	}

	return 0;
}

static noinline __maybe_unused
int PATCHED_SYM(hog_cpu_interruptible_set)(void *data, u64 val)
{
	PATCHED_SYM(do_hog_cpu)((unsigned long)val, true);
	return 0;
}

static noinline __maybe_unused
int PATCHED_SYM(hog_cpu_uninterruptible_set)(void *data, u64 val)
{
	PATCHED_SYM(do_hog_cpu)((unsigned long)val, false);
	return 0;
}


#endif
