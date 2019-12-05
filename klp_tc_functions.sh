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

function __klp_add_patched_func() {
    local PATCH_ID="$1"
    local FUNC="$2"

    echo -n "\t{\n"
    echo -n "\t\t.old_name = \"orig_${FUNC}\",\n"
    echo -n "\t\t.new_func = klp_${PATCH_ID}_${FUNC},\n"
    echo -n "\t},\n"
}

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
    local OUTPUT_DIR="$(dirname $SRC_FILE)"

    PATCH_FUNCS=""
    PATCH_GETPID=0
    while [ $# -gt 0 ]; do
	local FUNC="$1"
	shift

	if [ x"$FUNC" == x${KLP_TEST_SYSCALL_FN_PREFIX}sys_getpid ]; then
	    PATCH_GETPID=1
	    continue
	fi
	PATCH_FUNCS="${PATCH_FUNCS}$(__klp_add_patched_func $PATCH_ID $FUNC)"
    done

    mkdir -p "$(dirname "$SRC_FILE")"
    sed -f - "$TEMPLATE" > "${SRC_FILE}.tmp" <<EOF
s%@@PATCH_ID@@%$PATCH_ID%;
s%@@PATCH_GETPID@@%$PATCH_GETPID%;
s%@@SYSCALL_FN_PREFIX@@%$KLP_TEST_SYSCALL_FN_PREFIX%;
s%@@PATCH_REPLACE_ALL@@%$PATCH_REPLACE_ALL%;
s%@@PATCH_FUNCS@@%$PATCH_FUNCS%;
EOF
    if [ ! -e "${SRC_FILE}" ] || \
       ! diff "${SRC_FILE}" "${SRC_FILE}.tmp" > /dev/null 2>&1; then
	mv "${SRC_FILE}.tmp" "${SRC_FILE}"
    else
	rm "${SRC_FILE}.tmp"
    fi

    sed "s%@@USE_OLD_HRTIMER_API@@%$KLP_TEST_HRTIMER_OLD%" \
	    "${SOURCE_DIR}/klp_test_support_mod.h" \
	    > "${OUTPUT_DIR}/klp_test_support_mod.h"
}

# Compile a kernel module
# parameters: source file
function klp_compile_module() {
    local SRC_FILE="$1"
    local OUTPUT_DIR="$(dirname "$1")"

    echo "obj-m += " $(basename "$SRC_FILE" .c)".o" \
	> "$OUTPUT_DIR"/Makefile

    make -C /lib/modules/$(uname -r)/build \
        M="$OUTPUT_DIR" modules 1>&2
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

function klp_create_test_support_module() {
    local OUTPUT_DIR="$1"

    sed "s%@@USE_OLD_HRTIMER_API@@%$KLP_TEST_HRTIMER_OLD%" \
	    "${SOURCE_DIR}/klp_test_support_mod.h" \
	    > "${OUTPUT_DIR}/klp_test_support_mod.h"
    cp -u "${SOURCE_DIR}/klp_test_support_mod.c" "${OUTPUT_DIR}/"
    klp_compile_module "${OUTPUT_DIR}/klp_test_support_mod.c"
}

function klp_prepare_test_support_module() {
    local OUTPUT_DIR="$1"

    klp_tc_milestone "Compile test support module"
    local SUPPORT_KO="$(klp_create_test_support_module "$OUTPUT_DIR")"
    if [ $? -ne 0 ]; then
	return 1
    fi
    klp_tc_milestone "Load test support module"
    insmod "$SUPPORT_KO"
    if [ $? -ne 0 ]; then
	return 1
    fi

    register_mod_for_unload "$(basename $SUPPORT_KO .ko)"
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
    unset PIDS

    TRANSITIONING_PATCH="$(grep -l '^1$' /sys/kernel/livepatch/*/transition | head -n1)"
    echo "transitioning patch path: \"${TRANSITIONING_PATCH%/transition}\""

    if [ -n "$TRANSITIONING_PATCH" ]; then
	TRANSITION_DIRECTION=$(cat "${TRANSITIONING_PATCH/%\/transition/\/enabled}")

	for DIR in /proc/[0-9]*/task/[0-9]*; do
	    PATCH_STATE=$(cat $DIR/patch_state 2>/dev/null)
	    if [ -n "$PATCH_STATE" ] && [ "$PATCH_STATE" -ge 0 \
		-a "$PATCH_STATE" -ne "$TRANSITION_DIRECTION" ]; then
		PID=${DIR#/proc/}
		PID=${PID%/task/*}
		TID=${DIR#*/task/}
		COMM="$(cat $DIR/comm)"

		echo "$COMM ($PID/$TID) still in progress:"
		cat $DIR/stack
		echo -e '=============\n'
		PIDS="$PIDS $PID"
	    fi
	done
    fi

    if [ -z "$PIDS" ]; then
        echo "no threads with klp_in_progress set"
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
	if [ -d /sys/kernel/livepatch/"$P" ]; then
	    klp_tc_milestone "Disabling and removing module $P"
	    echo 0 > /sys/kernel/livepatch/"$P"/enabled
	    klp_wait_complete 61
	else
	    klp_tc_milestone "Removing module $P"
	fi
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

# detect environment settings
KLP_ENV_CACHE_FILE=/tmp/live-patch/klp_env_cache
if [ ! -f $KLP_ENV_CACHE_FILE ]; then
    mkdir -p $(dirname $KLP_ENV_CACHE_FILE)

    # compile-test for hrtimer API ()
    COMPILETEST_DIR=/tmp/live-patch/klp_compile_test
    mkdir -p $COMPILETEST_DIR
    cp "$SOURCE_DIR"/klp_compile_test_hrtimer.c $COMPILETEST_DIR/

    echo -n 'export KLP_TEST_HRTIMER_OLD=' > $KLP_ENV_CACHE_FILE
    if klp_compile_module $COMPILETEST_DIR/klp_compile_test_hrtimer.c > /dev/null 2>&1;
    then
        echo "1" >> $KLP_ENV_CACHE_FILE
    else
        echo "0" >> $KLP_ENV_CACHE_FILE
    fi

    # Check for getpid syscall prefix
    echo -n 'export KLP_TEST_SYSCALL_FN_PREFIX=' >> $KLP_ENV_CACHE_FILE

    # generate LINUX_VERSION_CODE from `uname -r`
    KVER="$(uname -r | cut -d- -f1)"
    PART1="$(echo $KVER | cut -d. -f1)"
    PART2="$(echo $KVER | cut -d. -f2)"
    PART3="$(echo $KVER | cut -d. -f3)"
    VERSION_CODE=$(((PART1 <<16) + (PART2 <<8) + PART3))

    if [ "$VERSION_CODE" -ge 266496 ] # test for kernel 4.17.0 and newer
    then
        case $(uname -m) in
            x86_64) echo "__x64_" >> $KLP_ENV_CACHE_FILE
                ;;
            s390x) echo "__s390x_" >> $KLP_ENV_CACHE_FILE
                ;;
            *) echo >> $KLP_ENV_CACHE_FILE
                ;;
        esac
    else
        echo >> $KLP_ENV_CACHE_FILE
    fi
fi
. $KLP_ENV_CACHE_FILE
