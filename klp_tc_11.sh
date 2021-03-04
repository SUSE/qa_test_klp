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

# Test Case 11: Patch function sleeping in a fault
# Patch a function which is sleeping in a write fault.
# The reliable stacktrace implementation must either discover this function
# or declare the stacktrace as unreliable.

set -e
. $(dirname $0)/klp_tc_functions.sh
klp_tc_init "Test Case 11: Patch a faulting function"

klp_tc_milestone "Compiling kernel live patch"
PATCH_KO="$(klp_create_patch_module tc_11 do_read_active_livepatch_id)"
PATCH_MOD_NAME="$(basename "$PATCH_KO" .ko)"

klp_tc_milestone "Compiling faulting_cat"
PATCH_DIR="/tmp/live-patch/tc_11"
gcc -o "$PATCH_DIR"/faulting_cat "$SOURCE_DIR"/klp_tc_11-faulting_cat.c -pthread

klp_prepare_test_support_module "$PATCH_DIR"

klp_tc_milestone "Running faulting_cat"
"$PATCH_DIR"/faulting_cat						\
	360 /sys/kernel/debug/klp_test_support/active_livepatch_id	\
	> /dev/null &
FAULTING_CAT_PID=$!
push_recovery_fn "kill $!"

klp_tc_milestone "Inserting live patch"
insmod "$PATCH_KO"
if [ ! -e /sys/kernel/livepatch/"$PATCH_MOD_NAME" ]; then
   klp_tc_abort "don't see $PATCH_MOD_NAME in live patch sys directory"
fi
register_mod_for_unload "$PATCH_MOD_NAME"

klp_tc_milestone "Check that live patch is blocked"
if klp_wait_complete "$PATCH_MOD_NAME" 10; then
    klp_tc_abort "patching finished prematurely"
fi

klp_tc_milestone "Terminating faulting_cat"
kill $FAULTING_CAT_PID
wait $FAULTING_CAT_PID || true

klp_tc_milestone "Wait for completion"
if ! klp_wait_complete "$PATCH_MOD_NAME" 61; then
    klp_dump_blocking_processes
    klp_tc_abort "patching didn't finish in time"
fi

klp_tc_exit
