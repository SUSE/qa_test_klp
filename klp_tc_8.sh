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

# Test Case 8: Patch with replace-all

set -e
. $(dirname $0)/klp_tc_functions.sh

klp_tc_init "Test Case 8: Patch with replace-all"

N_PATCHES=5

klp_tc_milestone "Compiling live patches"
PATCH_DIR="/tmp/live-patch/tc_8"
declare -a PATCH_KOS
for N in $(seq $N_PATCHES); do
    PATCH_SUBDIR="$PATCH_DIR/patch_replace-all_$N"
    PATCH_KOS[$N]="$(klp_create_patch_module -r -o "$PATCH_SUBDIR" tc_8_$N ${KLP_TEST_SYSCALL_FN_PREFIX}sys_getpid)"
done

for N in $(seq 1 $N_PATCHES); do
    klp_tc_milestone "Inserting getpid patch $N"
    PATCH_KO="${PATCH_KOS[$N]}"
    PATCH_MOD_NAME="$(basename "$PATCH_KO" .ko)"
    insmod "$PATCH_KO"

    klp_tc_milestone "Wait for completion ($PATCH_MOD_NAME)"
    if ! klp_wait_complete "$PATCH_MOD_NAME" 61; then
        klp_dump_blocking_processes
        klp_tc_abort "patching didn't finish in time ($PATCH_MOD_NAME)"
    fi
done

for N in $(seq 1 $((N_PATCHES - 1))); do
    klp_tc_milestone "Removing getpid patch $N"
    PATCH_KO="${PATCH_KOS[$N]}"
    PATCH_MOD_NAME="$(basename "$PATCH_KO" .ko)"
    if ! klp_wait_complete "$PATCH_MOD_NAME" 61; then
        klp_tc_abort "module reference count did not drop to zero ($PATCH_MOD_NAME)"
    fi
    rmmod "$PATCH_MOD_NAME"
    if test $? -ne 0;then
        klp_tc_abort "FAILED to remove the kernel module $PATCH_MOD_NAME"
    fi
done

klp_tc_milestone "Testing final patch removal"
PATCH_KO="${PATCH_KOS[$N_PATCHES]}"
PATCH_MOD_NAME="$(basename "$PATCH_KO" .ko)"
if rmmod "$PATCH_MOD_NAME"; then
    klp_tc_abort "It should not be possible to remove the kernel module ${PATCH_MOD_NAME}"
fi

register_mod_for_unload "$PATCH_MOD_NAME"

# test passed if execution reached this line
# failures beyond this point are not test case failures
klp_tc_exit
