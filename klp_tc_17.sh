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

# Test Case 17: Check that patching a kprobed function fails
# Patch a function with a kprobe on it and check that the live patch
# fails to load: kprobes' and live patching ftrace_ops both have
# FTRACE_OPS_FL_IPMODIFY set.

set -e
. $(dirname $0)/klp_tc_functions.sh
klp_tc_init "Test Case 17: Check that patching a kprobed function fails"

klp_tc_milestone "Compiling kernel live patch"
PATCH_KO="$(klp_create_patch_module tc_17 do_read_active_livepatch_id)"
PATCH_MOD_NAME="$(basename "$PATCH_KO" .ko)"

PATCH_DIR="/tmp/live-patch/tc_17"
klp_prepare_test_support_module "$PATCH_DIR"

klp_tc_milestone "Add kprobe to orig_do_read_active_livepatch_id"
echo -n orig_do_read_active_livepatch_id > /sys/kernel/debug/klp_test_support/add_kprobe

klp_tc_milestone "Try to insert live patch"
if insmod "$PATCH_DIR/$PATCH_MOD_NAME".ko > /dev/null 2>&1; then
   klp_tc_abort "loading patch module succeeded unexpectedly"
fi

klp_tc_milestone "Remove kprobe from orig_do_read_active_livepatch_id"
echo -n orig_do_read_active_livepatch_id > /sys/kernel/debug/klp_test_support/remove_probes

klp_tc_exit
