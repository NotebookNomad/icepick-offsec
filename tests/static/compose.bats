#!/usr/bin/env bats
# The compose file parses and interpolates against .env.

load '../test_helper/common'

setup() {
  command -v docker >/dev/null || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose v2 not available"
}

@test "docker-compose.yml validates" {
  run docker compose -f "${PROJECT_ROOT}/docker-compose.yml" --env-file "${PROJECT_ROOT}/.env" config -q
  assert_success
}

@test "NET_ADMIN and the tun device are declared" {
  run docker compose -f "${PROJECT_ROOT}/docker-compose.yml" --env-file "${PROJECT_ROOT}/.env" config
  assert_success
  assert_output --partial "NET_ADMIN"
  assert_output --partial "/dev/net/tun"
}
