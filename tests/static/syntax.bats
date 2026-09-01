#!/usr/bin/env bats
# Every shipped script parses.

load '../test_helper/common'

@test "deck: bash -n" {
  run bash -n "${PROJECT_ROOT}/deck"
  assert_success
}

@test "scripts/fetch-wordlists: bash -n" {
  run bash -n "${PROJECT_ROOT}/scripts/fetch-wordlists"
  assert_success
}

@test "scripts/lockdown-lan: bash -n" {
  run bash -n "${PROJECT_ROOT}/scripts/lockdown-lan"
  assert_success
}

@test "scripts/lockdown-wan: bash -n" {
  run bash -n "${PROJECT_ROOT}/scripts/lockdown-wan"
  assert_success
}

@test "scripts/vpn-connect: bash -n" {
  run bash -n "${PROJECT_ROOT}/scripts/vpn-connect"
  assert_success
}

@test "config/zshrc: zsh -n" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -n "${PROJECT_ROOT}/config/zshrc"
  assert_success
}

@test "tests/run.sh: bash -n" {
  run bash -n "${TESTS_DIR}/run.sh"
  assert_success
}
