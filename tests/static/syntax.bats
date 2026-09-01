#!/usr/bin/env bats
# Every shipped script parses. scripts/ is globbed so a newly added helper is
# covered automatically.

load '../test_helper/common'

@test "deck: bash -n" {
  run bash -n "${PROJECT_ROOT}/deck"
  assert_success
}

@test "every scripts/* parses (bash -n)" {
  local f rc=0
  for f in "${PROJECT_ROOT}"/scripts/*; do
    [ -f "$f" ] || continue
    bash -n "$f" || { echo "FAILED bash -n: $f"; rc=1; }
  done
  return "$rc"
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
