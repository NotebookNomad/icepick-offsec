# Shared setup for every .bats file. `load` this first.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
export TESTS_DIR PROJECT_ROOT

load "${TESTS_DIR}/test_helper/bats-support/load"
load "${TESTS_DIR}/test_helper/bats-assert/load"

# Put the fake binaries in tests/stubs/bin ahead of the real ones and start a
# fresh call log for this test. Every stub appends its argv to $STUB_CALLLOG.
use_stubs() {
  export STUB_CALLLOG="${BATS_TEST_TMPDIR}/calls.log"
  : > "$STUB_CALLLOG"
  export PATH="${TESTS_DIR}/stubs/bin:${PATH}"
}

# assert_called <extended-regex>  - a stub recorded a matching invocation
assert_called() {
  if ! grep -Eq -- "$1" "$STUB_CALLLOG"; then
    echo "expected a call matching: $1"
    echo "--- recorded calls ---"; cat "$STUB_CALLLOG"
    return 1
  fi
}

# refute_called <extended-regex>  - no stub recorded a matching invocation
refute_called() {
  if grep -Eq -- "$1" "$STUB_CALLLOG"; then
    echo "unexpected call matching: $1"
    echo "--- recorded calls ---"; cat "$STUB_CALLLOG"
    return 1
  fi
}

# Copy the parts of the repo that `deck` reads into an isolated dir and cd there.
# `deck` cd's to its own directory on startup, so tests invoke "$PWD/deck".
sandbox_deck() {
  local d="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$d/scripts" "$d/config" "$d/workspace" "$d/vpn"
  cp "$PROJECT_ROOT/deck" "$d/deck"
  cp "$PROJECT_ROOT/docker-compose.yml" "$d/"
  cp "$PROJECT_ROOT"/scripts/* "$d/scripts/"
  cp "$PROJECT_ROOT"/config/* "$d/config/"
  [ -f "$PROJECT_ROOT/.env" ] && cp "$PROJECT_ROOT/.env" "$d/"
  cd "$d" || return 1
}

fixture() { printf '%s\n' "${TESTS_DIR}/fixtures/$1"; }

# --- integration helpers ----------------------------------------------------
# Everything below needs Docker and a built image; the unit and static suites
# never touch them.

# Skip the whole file unless there is a docker, a compose v2, and an image to
# run. Called from setup(), where bats' skip aborts the test.
require_image() {
  command -v docker >/dev/null || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose v2 not available"
  docker image inspect icepick-offsec:latest >/dev/null 2>&1 \
    || skip "icepick-offsec:latest not built - run ./deck build"
}

# One throwaway container off the repo's own compose file, so the project name -
# and therefore the volumes - match what deck uses rather than spawning a
# parallel set. tests/run.sh builds first, so the image carries the working-tree
# scripts and nothing needs mounting over them.
compose_run() {
  docker compose -f "${PROJECT_ROOT}/docker-compose.yml" run --rm -T "$@"
}
