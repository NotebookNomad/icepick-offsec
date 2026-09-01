#!/usr/bin/env bats
# `deck vpn` argument parsing -> the flags it forwards to `docker compose run`.

load '../test_helper/common'

setup() {
  use_stubs
  sandbox_deck
  DECK="$PWD/deck"
  CERT="$(fixture ovpn/cert-only.ovpn)"
}

@test "--socks forwards the default port, loopback-bound" {
  run "$DECK" vpn "$CERT" --socks
  assert_success
  assert_called 'run --rm -e OVPN=cert-only\.ovpn -p 127\.0\.0\.1:1080:1080 -e SOCKS=1080 deck vpn-connect'
}

@test "--socks <port> overrides the port" {
  run "$DECK" vpn "$CERT" --socks 9050
  assert_success
  assert_called 'run --rm -e OVPN=cert-only\.ovpn -p 127\.0\.0\.1:9050:9050 -e SOCKS=9050 deck vpn-connect'
}

@test "--socks only consumes the next arg when it is a port number" {
  # `deck vpn --socks <cfg>`: the cfg must not be swallowed as the port.
  run "$DECK" vpn --socks "$CERT"
  assert_success
  assert_called 'run --rm -e OVPN=cert-only\.ovpn -p 127\.0\.0\.1:1080:1080 -e SOCKS=1080 deck vpn-connect'
}

@test "--lockdown forwards EGRESS_FIREWALL and nothing socks-related" {
  run "$DECK" vpn "$CERT" --lockdown
  assert_success
  assert_called 'run --rm -e OVPN=cert-only\.ovpn -e EGRESS_FIREWALL=on deck vpn-connect'
  refute_called ' -p '
  refute_called 'SOCKS'
}

@test "--socks and --lockdown compose" {
  run "$DECK" vpn "$CERT" --socks --lockdown
  assert_success
  assert_called 'run --rm -e OVPN=cert-only\.ovpn -p 127\.0\.0\.1:1080:1080 -e SOCKS=1080 -e EGRESS_FIREWALL=on deck vpn-connect'
}

@test "plain: just the config, no publish, no firewall" {
  run "$DECK" vpn "$CERT"
  assert_success
  assert_called 'run --rm -e OVPN=cert-only\.ovpn deck vpn-connect'
  refute_called ' -p '
  refute_called 'EGRESS_FIREWALL'
}

@test "no config: usage error, exit 1, nothing launched" {
  run "$DECK" vpn
  assert_failure
  assert_output --partial "usage: ./deck vpn <file.ovpn>"
  refute_called '^docker '
}

@test "missing file: clear error, exit 1, nothing launched" {
  run "$DECK" vpn /no/such/lab.ovpn
  assert_failure
  assert_output --partial "no such file: /no/such/lab.ovpn"
  refute_called '^docker '
}

@test "unknown flag: rejected, exit 1, nothing launched" {
  run "$DECK" vpn "$CERT" --turbo
  assert_failure
  assert_output --partial "unknown option: --turbo"
  refute_called '^docker '
}

@test "the config is staged into workspace/" {
  run "$DECK" vpn "$CERT"
  assert_success
  [ -f "$PWD/workspace/cert-only.ovpn" ]
}
