#!/usr/bin/env bats
# shellcheck at --severity=warning: catches real defects (bad quoting that
# breaks, unset vars, unreachable code) without nagging about the deliberate
# word-splitting in `deck` and `lockdown-wan`, which is `info`-level.

load '../test_helper/common'

setup() {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
}

@test "deck" {
  run shellcheck -x --severity=warning "${PROJECT_ROOT}/deck"
  assert_success
}

@test "scripts/*" {
  run shellcheck -x --severity=warning \
    "${PROJECT_ROOT}/scripts/fetch-wordlists" \
    "${PROJECT_ROOT}/scripts/lockdown-lan" \
    "${PROJECT_ROOT}/scripts/lockdown-wan" \
    "${PROJECT_ROOT}/scripts/vpn-connect"
  assert_success
}

@test "test harness (run.sh, common.bash, stubs)" {
  run shellcheck -x --severity=warning -e SC1090,SC1091 \
    "${TESTS_DIR}/run.sh" \
    "${TESTS_DIR}/test_helper/common.bash" \
    "${TESTS_DIR}"/stubs/bin/*
  assert_success
}
