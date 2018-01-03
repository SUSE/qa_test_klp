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

# define useful variables
readonly SOURCE_DIR="$(dirname $0)"

# compile a live patch module
# parameters: output directory, source file
function klp_compile_patch_module() {
    PATCH_OUTPUT_DIR="$1"
    SOURCE_FILE="$2"
    DEST_FILE="$PATCH_OUTPUT_DIR"/$(basename "$SOURCE_FILE")

    mkdir -p "$PATCH_OUTPUT_DIR"
    echo "obj-m += " $(basename "$SOURCE_FILE" .c)".o" \
	> "$PATCH_OUTPUT_DIR"/Makefile

    # detect if source and destination are the same file
    if [ ! -e "$DEST_FILE" ] || \
	[ $(stat -c %i "$SOURCE_FILE") -ne $(stat -c %i "$DEST_FILE") ]; then
	cp -fv "$SOURCE_FILE" "$DEST_FILE"
    fi

    KERN_VERSION=$(uname -r | sed 's/-[^-]*$//')
    KERN_FLAVOR=$(uname -r | sed 's/^.*-//')
    KERN_ARCH=$(uname -m)
    make -C /usr/src/linux-$KERN_VERSION-obj/$KERN_ARCH/$KERN_FLAVOR \
	M="$PATCH_OUTPUT_DIR" O="$PATCH_OUTPUT_DIR"
}

function klp_in_progress() {
    for p in /sys/kernel/livepatch/*; do
            [ 0$(cat "$p/transition" 2>/dev/null) -ne 0 ] && return 0
    done
    return 1
}

function klp_wait_complete() {
    if [ $# -gt 0 ]; then
        TIMEOUT=$1
    else
        TIMEOUT=-1
    fi

    while klp_in_progress && [ $TIMEOUT -ne 0 ]; do
        sleep 1
        (( TIMEOUT-- )) || true
    done

    ! klp_in_progress
}

function klp_dump_blocking_processes() {
    return 0 # until upstream receives a consistency model

    unset PIDS
    echo "global live patching in_progress flag:" $(cat /sys/kernel/livepatch/in_progress)

    for PROC in /proc/[0-9]*; do
        if [ "$(cat $PROC/klp_in_progress)" -ne 0 ]; then
	    DIR=${PROC%/klp_in_progress}
	    PID=${DIR#/proc/}
	    COMM="$(cat $DIR/comm)"

	    echo "$COMM ($PID) still in progress:"
	    cat $DIR/stack
	    echo -e '=============\n'
	    PIDS="$PIDS $PID"
	fi
    done
    if [ -z "$PIDS" ]; then
        echo "no processes with klp_in_progress set"
    fi
}

declare -a RECOVERY_HOOKS

function push_recovery_fn() {
    [ -z "$1" ] && echo "WARNING: no parameters passed to push_recovery_fn"
    RECOVERY_HOOKS[${#RECOVERY_HOOKS[*]}]="$1"
}

function pop_and_run_recovery_fn() {
    local fn=$1
    local num_hook=${#RECOVERY_HOOKS[*]}

    [ $num_hook -eq 0 ] && return 1
    (( num_hook--)) || true
    eval ${RECOVERY_HOOKS[$num_hook]} || true
    unset RECOVERY_HOOKS[$num_hook]
    return 0
}

function call_recovery_hooks() {
    for fn in "${RECOVERY_HOOKS[@]}"; do
        echo "calling \"$fn\""
        eval $fn || true
    done
}

function klp_tc_write() {
    logger "$*"
    echo "$*"
}

function klp_tc_init() {
    trap "[ \$? -ne 0 ] && echo TEST FAILED while executing \'\$BASH_COMMAND\', EXITING; call_recovery_hooks" EXIT
    klp_tc_write "$1"
    if klp_in_progress; then
        klp_tc_write "ERROR kernel live patching in progress, cannot start test"
	exit 22 # means SKIPPED in CTCS2 terminology
    fi
}

function klp_tc_milestone() {
    klp_tc_write "***" "$*"
}

function klp_tc_abort() {
    klp_tc_write "TEST CASE ABORT" "$*"
    exit 1
}
