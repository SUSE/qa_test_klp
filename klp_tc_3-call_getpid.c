/*
 * Copyright (C) 2017 SUSE
 * Author: Libor Pechacek
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 */

#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <signal.h>

int run = 1;
int sig_int;

void hup_handler(int signum)
{
	run = 0;
}

void int_handler(int signum)
{
	run = 0;
	sig_int = 1;
}

int main(int argc, char *argv[])
{
	pid_t orig_pid, pid;
	long count = 0;

	signal(SIGHUP, &hup_handler);
	signal(SIGINT, &int_handler);

	orig_pid = syscall(SYS_getpid);

	while(run) {
		pid = syscall(SYS_getpid);
		if (pid != orig_pid)
			return 1;
		count++;
	}

	if (sig_int)
		printf("%d iterations done\n", count);

	return 0;
}
