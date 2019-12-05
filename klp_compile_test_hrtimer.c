#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/hrtimer.h>

static int __init compile_test_mod_init(void)
{
	struct hrtimer_sleeper t;
	hrtimer_init_sleeper(&t, current);
	return 0;
}

static void __exit compile_test_mod_exit(void)
{
}

module_init(compile_test_mod_init);
module_exit(compile_test_mod_exit);
