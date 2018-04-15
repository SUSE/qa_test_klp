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


# Create a livepatch source file from template
# Parameters:
#  - output file name
#  - livepatch id
#  - replace-all: either true or false
#  - list of to be patched functions
function klp_create_patch_module_src() {
    local TEMPLATE="${SOURCE_DIR}/klp_test_livepatch.c"
    local SRC_FILE="$1"
    local PATCH_ID="$2"
    local PATCH_REPLACE_ALL="$3"
    shift 3

    PATCH_GETPID=0
    while [ $# -gt 0 ]; do
	local FUNC="$1"
	shift

	if [ x"$FUNC" == xsys_getpid ]; then
	    PATCH_GETPID=1
	    continue
	fi
    done

    mkdir -p "$(dirname "$SRC_FILE")"
    sed -f - "$TEMPLATE" > "${SRC_FILE}.tmp" <<EOF
s%@@PATCH_ID@@%$PATCH_ID%;
s%@@PATCH_GETPID@@%$PATCH_GETPID%;
s%@@PATCH_REPLACE_ALL@@%$PATCH_REPLACE_ALL%;
EOF
    if [ ! -e "${SRC_FILE}" ] || \
       ! diff "${SRC_FILE}" "${SRC_FILE}.tmp" > /dev/null 2>&1; then
	mv "${SRC_FILE}.tmp" "${SRC_FILE}"
    else
	rm "${SRC_FILE}.tmp"
    fi
}

# Compile a kernel module
# parameters: source file
function klp_compile_module() {
    local SRC_FILE="$1"
    local OUTPUT_DIR="$(dirname "$1")"

    echo "obj-m += " $(basename "$SRC_FILE" .c)".o" \
	> "$OUTPUT_DIR"/Makefile

    KERN_VERSION=$(uname -r | sed 's/-[^-]*$//')
    KERN_FLAVOR=$(uname -r | sed 's/^.*-//')
    KERN_ARCH=$(uname -m)
    make -C /usr/src/linux-$KERN_VERSION-obj/$KERN_ARCH/$KERN_FLAVOR \
	M="$OUTPUT_DIR" O="$OUTPUT_DIR" 1>&2
    if [ $? -ne 0 ]; then
	return 1
    fi
    echo "${SRC_FILE%.c}.ko"
}

# Create a livepatch module from template
# Parameters:
#  - optional -r: create "replace-all" live patch
#  - optional -o <dir>: output directory (default: /tmp/live-patch/<patch-id>)
#  - livepatch id
#  - list of to be patched functions
function klp_create_patch_module() {
    local REPLACE_ALL=false
    local OUTPUT_DIR

    local OPTIND=1
    local OPTARG
    local O
    while getopts ':ro:' O; do
	case "$O" in
	    'r')
		REPLACE_ALL=true
		;;

	    'o')
		OUTPUT_DIR="$OPTARG"
		;;

	    '?')
		echo -n "error: klp_create_patch_module: invalid parameter" 1>&2
		echo " '$OPTARG'" 1>&2
		return 1
		;;
	esac
    done
    shift $((OPTIND-1))

    local PATCH_ID="$1"
    shift

    OUTPUT_DIR="${OUTPUT_DIR:-/tmp/live-patch/${PATCH_ID}}"

    local SRC_FILE="${OUTPUT_DIR}/klp_${PATCH_ID}_livepatch.c"
    klp_create_patch_module_src "$SRC_FILE" "$PATCH_ID" "$REPLACE_ALL" "$@"
    klp_compile_module "$SRC_FILE"
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
    # timestamp every line of output
    exec > >(awk '{ print strftime("[%T] ") $0 }')
    exec 2>&1
    klp_tc_write "$1"
    if klp_in_progress; then
        klp_tc_write "ERROR kernel live patching in progress, cannot start test"
	exit 22 # means SKIPPED in CTCS2 terminology
    fi
}

declare -a MODULES_LOADED

function register_mod_for_unload() {
    [ -z "$1" ] && echo "WARNING: no parameters passed to register_mod_for_unload"
    MODULES_LOADED=("$1" ${MODULES_LOADED[@]})
}

function klp_tc_exit() {
    trap - EXIT

    klp_tc_milestone "Removing patches"

    for P in ${MODULES_LOADED[@]}; do
	klp_tc_milestone "Disabling and removing module $P"
	echo 0 > /sys/kernel/livepatch/"$P"/enabled
	klp_wait_complete 61
	rmmod "$P"
    done

    klp_tc_milestone "TEST PASSED"
}

function klp_tc_milestone() {
    klp_tc_write "***" "$*"
}

function klp_tc_abort() {
    klp_tc_write "TEST CASE ABORT" "$*"
    exit 1
}
