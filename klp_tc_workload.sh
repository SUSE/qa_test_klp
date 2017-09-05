# Copyright (C) 2017 SUSE
# Authors: Lance Wang
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

declare -a WORKLOAD_LIST
function add_workload {
    [ -z "$1" ]  && echo "WARNING: no parameters passed to $FUNCNAME"
    case $1 in
        cpu):;;
        mem):;;
        *) echo "WARNING: $1 dose not exist";return 1;;
    esac
    WORKLOAD_LIST[${#WORKLOAD_LIST[*]}]="$1"
}

function start_workload {
    for w in "${WORKLOAD_LIST[@]}"; do
        echo "start ${w}"
        eval "workload_$w > /dev/null"
    done
}

function workload_A_start {
    local pid
    cat /dev/urandom > /dev/null &
    pid=$!
    if test "X$(type -t push_recovery_fn)" == "Xfunction"; then
        push_recovery_fn "kill $pid"
    fi
}

function workload_cpu {
    echo "WORKLOAD cpu"

    for i in $(seq 1 $(nproc)); do
        workload_A_start
    done
}

function workload_mem {
    local pid
    local CHIMEM_BIN="/usr/bin/chimem"

    if [ -e "$SOURCE_DIR/bin/chimem"] ; then
        CHIMEM_BIN="$SOURCE_DIR/bin/chimem"
    fi

    echo "WORKLOAD memory"

    ${CHIMEM_BIN} &
    pid=$!
    if test "X$(type -t push_recovery_fn)" == "Xfunction"; then
        push_recovery_fn "kill $pid"
    fi
}
