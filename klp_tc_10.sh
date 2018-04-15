#!/bin/bash

# Copyright (C) 2018 SUSE
# Author: Nicolai Stange
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.

# Test Case 10: Patch caller of graph traced callee
# Sleep in a graph traced function called from the patched one.
# Reliable stacktraces must include the caller and prevent patching
# from succeeding.

set -e
. $(dirname $0)/klp_tc_functions.sh
klp_tc_init "Test Case 10: Patch caller of graph traced callee"

klp_tc_milestone "Compiling kernel live patch"
PATCH_KO="$(klp_create_patch_module tc_10 sleep_uninterruptible_set)"
PATCH_MOD_NAME="$(basename "$PATCH_KO" .ko)"

PATCH_DIR="/tmp/live-patch/tc_10"
klp_prepare_test_support_module "$PATCH_DIR"

klp_tc_milestone "Enable graph tracing for orig_do_sleep"
echo "orig_do_sleep" > /sys/kernel/debug/tracing/set_ftrace_filter
echo "function_graph" > /sys/kernel/debug/tracing/current_tracer

klp_tc_milestone "Starting uninterruptible sleeper"
echo 15 > /sys/kernel/debug/klp_test_support/sleep_uninterruptible &
SLEEP_PID=$!

klp_tc_milestone "Inserting live patch"
insmod "$PATCH_DIR/$PATCH_MOD_NAME".ko
if [ ! -e /sys/kernel/livepatch/"$PATCH_MOD_NAME" ]; then
   klp_tc_abort "don't see $PATCH_MOD_NAME in live patch sys directory"
fi
register_mod_for_unload "$PATCH_MOD_NAME"

klp_tc_milestone "Check that live patch is blocked"
if klp_wait_complete 10; then
    klp_tc_abort "patching finished prematurely"
fi

klp_tc_milestone "Waiting for uninterruptible sleeper"
wait $SLEEP_PID

klp_tc_milestone "Reset graph tracing"
echo "nop" > /sys/kernel/debug/tracing/current_tracer
echo "" > /sys/kernel/debug/tracing/set_ftrace_filter

klp_tc_milestone "Wait for completion"
if ! klp_wait_complete 61; then
    klp_dump_blocking_processes
    klp_tc_abort "patching didn't finish in time"
fi

klp_tc_exit
