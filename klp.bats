#!/usr/bin/env bats

@test "Patch under pressure" {
    ./klp_tc_3.sh
}

@test "Test live kernel patching in quick succession" {
    ./klp_tc_5.sh
}

@test "Patch while CPUs are busy" {
    ./klp_tc_6.sh
}

@test "Patch in low memory condition" {
    ./klp_tc_7.sh
}

@test "Patch with replace-all" {
    ./klp_tc_8.sh
}

@test "Patch caller of graph traced callee" {
    ./klp_tc_10.sh
}

@test "Patch function sleeping in a fault" {
    ./klp_tc_11.sh
}

@test "Patch caller of kretprobed callee" {
    ./klp_tc_12.sh
}

@test "Patch traced function" {
    ./klp_tc_13.sh
}

@test "Trace patched function" {
    ./klp_tc_14.sh
}

@test "Patch graph-traced function" {
    ./klp_tc_15.sh
}

@test "Graph-trace patched function" {
    ./klp_tc_16.sh
}
