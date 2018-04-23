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

# Test Case 16: Graph-trace patched function
# Graph-trace a patched function and check that the live patch remains
# in effect.

set -e
. $(dirname $0)/klp_tc_functions.sh
klp_tc_init "Test Case 16: Graph-trace patched function"

klp_tc_milestone "Compiling kernel live patch"
PATCH_KO="$(klp_create_patch_module tc_16 do_read_active_livepatch_id)"
PATCH_MOD_NAME="$(basename "$PATCH_KO" .ko)"

PATCH_DIR="/tmp/live-patch/tc_16"
klp_prepare_test_support_module "$PATCH_DIR"

klp_tc_milestone "Inserting live patch"
insmod "$PATCH_DIR/$PATCH_MOD_NAME".ko
if [ ! -e /sys/kernel/livepatch/"$PATCH_MOD_NAME" ]; then
   klp_tc_abort "don't see $PATCH_MOD_NAME in live patch sys directory"
fi
register_mod_for_unload "$PATCH_MOD_NAME"

klp_tc_milestone "Wait for completion"
if ! klp_wait_complete 61; then
    klp_dump_blocking_processes
    klp_tc_abort "patching didn't finish in time"
fi

klp_tc_milestone "Enable graph tracing for orig_do_read_active_livepatch_id"
echo "orig_do_read_active_livepatch_id" > /sys/kernel/debug/tracing/set_ftrace_filter
echo "function_graph" > /sys/kernel/debug/tracing/current_tracer
echo "" > /sys/kernel/debug/tracing/trace

klp_tc_milestone "Check that live patch is in effect"
if [ x"$(cat /sys/kernel/debug/klp_test_support/active_livepatch_id)" != xtc_16 ]; then
    klp_tc_abort "live patch loaded but not effective"
fi

klp_tc_milestone "Reset graph tracing"
echo "nop" > /sys/kernel/debug/tracing/current_tracer
echo "" > /sys/kernel/debug/tracing/set_ftrace_filter
echo "" > /sys/kernel/debug/tracing/trace


klp_tc_exit
