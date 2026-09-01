#!/usr/bin/env bats
# shellcheck at --severity=warning: catches real defects (bad quoting that
# breaks, unset vars, unreachable code) without nagging about the deliberate
# word-splitting in `deck` and `lockdown-wan`, which is `info`-level.
#
# deck + scripts/* are globbed so a newly added script can't skip the gate.

load '../test_helper/common'

setup() {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
}

@test "deck and every scripts/*" {
  run shellcheck -x --severity=warning "${PROJECT_ROOT}/deck" "${PROJECT_ROOT}"/scripts/*
  assert_success
}

@test "test harness (run.sh, common.bash, stubs)" {
  run shellcheck -x --severity=warning -e SC1090,SC1091 \
    "${TESTS_DIR}/run.sh" \
    "${TESTS_DIR}/test_helper/common.bash" \
    "${TESTS_DIR}"/stubs/bin/*
  assert_success
}
