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
    # not possible with KLP as of v4.10
    skip
    ./klp_tc_8.sh
}

