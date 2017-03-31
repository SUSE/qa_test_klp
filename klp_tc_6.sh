#!/bin/bash

# Copyright (C) 2017 SUSE
# Authors: Lance Wang, Libor Pechacek
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

# Test Case 6: Patch while CPUs are busy
# Unlike in TC 3 we are not invoking the patched function

set -e
. $(dirname $0)/klp_tc_functions.sh
. $(dirname $0)/klp_tc_workload.sh

klp_tc_init "Test Case 6: Patch while CPUs are busy"

klp_tc_milestone "Compiling live patch"
PATCH_DIR="/tmp/live-patch/tc_6"
PATCH_MOD_NAME="klp_tc_6_live_patch_getpid"
klp_compile_patch_module "$PATCH_DIR" "$SOURCE_DIR/$PATCH_MOD_NAME".c

add_workload cpu
klp_tc_milestone "Starting workload"
start_workload

klp_tc_milestone "Inserting getpid patch"
insmod "$PATCH_DIR/$PATCH_MOD_NAME".ko
if [ ! -e /sys/kernel/livepatch/"$PATCH_MOD_NAME" ]; then
   klp_tc_abort "don't see $PATCH_MOD_NAME in live patch sys directory"
fi

klp_tc_milestone "Wait for completion"
if ! klp_wait_complete 61; then
    klp_dump_blocking_processes
    klp_tc_abort "patching didn't finish in time"
fi

# test passed if execution reached this line
# failures beyond this point are not test case failures
trap - EXIT
klp_tc_milestone "Call hooks before exit"
call_recovery_hooks
klp_tc_milestone "TEST PASSED, reboot to remove the live patch"
