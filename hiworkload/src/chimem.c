// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Copyright (C) 2017 SUSE
 * Author: Lance Wang <lzwang@suse.com>
 */

#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <errno.h>

/* the work loop */
static int wloop_goon;

void
wloop_reset(void)
{
    wloop_goon = 1;
}

void
wloop_run(void)
{
    while (wloop_goon != 0) {
        /* do nothing currently */
        asm("nop" ::: "memory");
    }
}

void
wloop_stop(void)
{
    wloop_goon = 0;
}

/* signal */
void
sig_handler_term(int signum)
{
    wloop_stop();
}

int
sig_install_handlers(void)
{
    int ret;
    struct sigaction sa_term;

    bzero(&sa_term, sizeof(sa_term));
    sa_term.sa_handler = sig_handler_term;

    ret = sigaction(SIGTERM, &sa_term, NULL);
    return ret;
}

/* eat memory  */
int
mem_eat(size_t length)
{
    void *addr;

    addr = mmap(NULL, length, PROT_READ | PROT_WRITE,
                MAP_LOCKED | MAP_ANONYMOUS | MAP_PRIVATE,
                -1, 0);

    if (MAP_FAILED == addr) {
        return -1;
    }
    return 0;
}

/* team */
#define MIN_MEM_PER_WORKER 32 * 1024 * 1024
#define WORKER_MAX 128
pid_t worker_ID[WORKER_MAX];
int worker_ID_I;

void
team_init(void)
{
    int i;

    for (i = 0; i < WORKER_MAX; i++) {
        worker_ID[i] = 0;
    }
    worker_ID_I = 0;
}

void
team_add_worker(pid_t id)
{
    if (worker_ID_I < WORKER_MAX) {
        worker_ID[worker_ID_I] = id;
        worker_ID_I++;
    } else {
        fprintf(stderr, "TOO many workers!!!\n");
    }
}

void
team_kill_worker(void)
{
    int i;

    for (i = 0; i < worker_ID_I; i++) {
        kill(worker_ID[i], SIGTERM);
    }
}

/* worker task */
void
worker (size_t length)
{
    int ret;

    ret = mem_eat(length);
    if (ret < 0) {
        fprintf(stderr, "%lu failed alloc memory: %s\n",
                getpid(), strerror(errno));
        exit(5);
    }
    /* todo SET proc name */
    wloop_reset();
    wloop_run();
    fprintf(stdout, "%lu finished.\n", getpid());
}

/* leader */
int
leader (int num_worker, size_t length_per_worker)
{
    int ret;
    int i;

    ret = sig_install_handlers();
    if (ret < 0) {
        fprintf(stderr, "%lu failed to install sig handlers\n",
                getpid());
        exit(22);
    }

    for (i = 0; i < num_worker; i++) {
        ret = fork();
        if (ret == 0) {
            worker(length_per_worker);
            exit(0);
        } else if (ret < 0) {
            fprintf(stderr, "FAILED to fork!\n");
        } else {
            int pid = ret;
            team_add_worker(pid);
        }
    }

    /* waiting */
    wloop_reset();
    wloop_run();

    /* get childs */
    team_kill_worker();
    /* wait ?? */
    exit(0);
}

/* main */
int
main (int argc, char **argv)
{
    size_t linelen = 0;
    char *line = NULL;
    unsigned long freemem = 0;
    unsigned long lowmem = 0;
    unsigned long mem_per_worker;
    int worker_num;

    FILE *f = fopen("/proc/meminfo", "r");
    while (getdelim(&line, &linelen, '\n', f) > 0) {
        sscanf(line, "LowFree: %lu", &lowmem);
		sscanf(line, "MemFree: %lu", &freemem);
    }
	/* If system is configured with HIGH memory, use LowFree,
	* else use MemFree */
	if (lowmem) {
		freemem = lowmem;
	}

    freemem *= 1024;

    if (freemem < MIN_MEM_PER_WORKER) {
        fprintf(stderr, "Memory is very low\n");
        exit(1);
    }

    mem_per_worker = freemem / WORKER_MAX;
    while (mem_per_worker < MIN_MEM_PER_WORKER) {
        mem_per_worker *= 2;
    }

    worker_num = freemem / mem_per_worker;
    printf("worker_num %d, mem_per_worker %luKib\n", worker_num, mem_per_worker / 1024);

    leader(worker_num, mem_per_worker);
    return 0;
}
