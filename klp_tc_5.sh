#!/bin/bash

# Copyright (C) 2017 SUSE
# Author: Libor Pechacek
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

# Test Case 5: Test live kernel patching in quick succession
# Apply one patch after another in quick succession

set -e
. $(dirname $0)/klp_tc_functions.sh
klp_tc_init "Test Case 5: Test live kernel patching in quick succession"

N_PATCHES=15

klp_tc_milestone "Compiling live patches"
PATCH_DIR="/tmp/live-patch/tc_5"
PATCH_MOD_NAME="klp_tc_5_live_patch_getpid"
for N in $(seq 1 $N_PATCHES); do
    PATCH_SUBDIR="$PATCH_DIR/patch$N"
    mkdir -p "$PATCH_SUBDIR"
    cp -v "$SOURCE_DIR/$PATCH_MOD_NAME".c \
	"$PATCH_SUBDIR/$PATCH_MOD_NAME$N".c
    klp_compile_patch_module "$PATCH_SUBDIR" "$PATCH_SUBDIR/$PATCH_MOD_NAME$N".c
done

for N in $(seq 1 $N_PATCHES); do
    PATCH_SUBDIR="$PATCH_DIR/patch$N"
    klp_tc_milestone "Inserting getpid patch $N"
    insmod "$PATCH_SUBDIR/$PATCH_MOD_NAME$N".ko

    klp_tc_milestone "Wait for completion (patch $N)"
    if ! klp_wait_complete 61; then
	klp_dump_blocking_processes
	klp_tc_abort "patching didn't finish in time (patch $N)"
    fi
done

# test passed if execution reached this line
# failures beyond this point are not test case failures
trap - EXIT
klp_tc_milestone "TEST PASSED, reboot to remove the live patches"
