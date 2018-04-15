/*
 * faulting_cat - cat like program with sleep on (write) fault at copy buffer
 *
 * Copyright (C) 2018 SUSE
 * Author: Nicolai Stange
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

#define _GNU_SOURCE
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <assert.h>
#include <pthread.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <limits.h>
#include <time.h>

#include <linux/userfaultfd.h>

#define ME "faulting-cat"

static void usage(void)
{
	fprintf(stderr, "usage: " ME " <fault_sleep_sec> <file>\n");
}

struct do_fault_data
{
	unsigned long fault_sleep_sec;
	int uffd;
	void *buf;
	size_t buf_size;
	pthread_t kill_on_error;
};

static void* do_fault(void * d)
{
	struct do_fault_data const *dfd = d;
	struct uffd_msg msg;
	struct uffdio_zeropage zp;
	struct timespec ts = {
		.tv_sec = dfd->fault_sleep_sec,
	};

	if (read(dfd->uffd, &msg, sizeof(msg)) < 0) {
		perror(ME ": read userfaultfd");
		pthread_kill(dfd->kill_on_error, SIGTERM);
		return (void *)-1;
	}

	assert(msg.event == UFFD_EVENT_PAGEFAULT);
	assert((void *)msg.arg.pagefault.address == dfd->buf);

	nanosleep(&ts, NULL);

	zp.mode = 0;
	zp.range = (struct uffdio_range){
		.start = msg.arg.pagefault.address,
		.len = dfd->buf_size,
	};
	if(ioctl(dfd->uffd, UFFDIO_ZEROPAGE, &zp)) {
		perror(ME ": ioctl UFFDIO_ZEROPAGE");
		pthread_kill(dfd->kill_on_error, SIGTERM);
		return (void *)-1;
	}
	return 0;
}

int main(int argc, char *argv[])
{
	int r = 0;
	unsigned long fault_sleep_sec;
	char *endptr;
	long page_size;
	int fd;
	void *buf;
	ssize_t bytes_written, bytes_read;
	size_t bytes_left;
	int uffd;
	struct uffdio_api api = { .api = UFFD_API };
	struct uffdio_register reg;
	struct do_fault_data dfd;
	pthread_t do_fault_thread;
	void *do_fault_thread_retval;

	if (argc != 3) {
		usage();
		return 1;
	}

	fault_sleep_sec = strtoul(argv[1], &endptr, 10);
	if (*endptr || endptr == argv[1]) {
		fprintf(stderr,
			ME ": error: could not parse fault_sleep_sec\n");
		usage();
		return 1;
	}

	page_size = sysconf(_SC_PAGESIZE);
	if (page_size < 0) {
		perror(ME ": sysconf _SC_PAGESIZE");
		return 2;
	}

	fd = open(argv[2], O_RDONLY);
	if (fd < 0) {
		perror(ME ": open");
		return 2;
	}

	uffd = syscall(__NR_userfaultfd, 0);
	if (uffd < 0) {
		perror(ME ": userfaultfd");
		close(fd);
		return 2;
	}

	if (ioctl(uffd, UFFDIO_API, &api)) {
		perror(ME ": ioctl UFFDIO_API");
		close(uffd);
		close(fd);
		return 2;
	}

	buf = mmap(NULL, (size_t)page_size, PROT_READ | PROT_WRITE,
		   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (buf == (void *)-1) {
		perror(ME ": mmap");
		close(uffd);
		close(fd);
		return 2;
	}

	reg.range = (struct uffdio_range){
		.start = (__u64)buf,
		.len = (size_t)page_size,
	};
	reg.mode = UFFDIO_REGISTER_MODE_MISSING;
	if (ioctl(uffd, UFFDIO_REGISTER, &reg)) {
		perror(ME ": ioctl UFFDIO_REGISTER");
		munmap(buf, (size_t)page_size);
		close(uffd);
		close(fd);
		return 2;
	}

	dfd = (struct do_fault_data) {
		.fault_sleep_sec = fault_sleep_sec,
		.uffd = uffd,
		.buf = buf,
		.buf_size = (size_t)page_size,
		.kill_on_error = pthread_self(),
	};
	if (pthread_create(&do_fault_thread, NULL, do_fault, &dfd)) {
		perror(ME ": pthread_create");
		munmap(buf, (size_t)page_size);
		close(uffd);
		close(fd);
		return 2;
	}

	bytes_written = 0;
	while ((bytes_read = read(fd, buf, (size_t)page_size)) > 0) {
		bytes_left = bytes_read;
		while (bytes_left) {
			void *p = (char *)buf + bytes_read - bytes_left;

			bytes_written = write(1, p, bytes_left);
			if (bytes_written < 0) {
				perror(ME ": write");
				break;
			}
			bytes_left -= bytes_written;
		}

		if (bytes_written < 0)
			break;
	}
	if (bytes_read < 0)
		perror(ME ": read");

	if (bytes_read < 0 || bytes_written < 0) {
		r = 2;
	}
	pthread_cancel(do_fault_thread);
	if (pthread_join(do_fault_thread, &do_fault_thread_retval)) {
		perror(ME ": pthread_join");
		r = r ? r : 2;
	}

	if (do_fault_thread_retval)
		r = r ? : 2;

	munmap(buf, (size_t)page_size);
	close(uffd);
	close(fd);

	return r;
}
