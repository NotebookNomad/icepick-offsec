#!/usr/bin/env bats
# `deck listen` address detection: the block that regressed once already
# (one address presented as authoritative when it was a guess).

load '../test_helper/common'

setup() {
  use_stubs
  sandbox_deck
  DECK="$PWD/deck"
}

@test "single-homed: prints the default-route address, nothing else" {
  export STUB_IP_ROUTE="1.1.1.1 via 203.0.113.1 dev enp1s0 src 203.0.113.10 uid 0"
  export STUB_IP_ADDRS="$(fixture ip-addrs/single-homed.txt)"

  run "$DECK" listen 4444

  assert_success
  assert_output --partial "listener ports published on the host : 4444"
  assert_output --partial "203.0.113.10   (host default route)"
  refute_output --partial "another address on this host"
}

@test "multi-homed: default-route addr is the guess, tailnet addr is listed too" {
  export STUB_IP_ROUTE="1.1.1.1 via 203.0.113.1 dev enp1s0 src 203.0.113.10 uid 0"
  export STUB_IP_ADDRS="$(fixture ip-addrs/tailscale-and-bridges.txt)"

  run "$DECK" listen 4444

  assert_success
  assert_output --partial "203.0.113.10   (host default route)"
  assert_output --partial "another address on this host         : 100.75.189.84"
}

@test "docker/bridge/virbr addresses are filtered out of the list" {
  export STUB_IP_ROUTE="1.1.1.1 via 203.0.113.1 dev enp1s0 src 203.0.113.10 uid 0"
  export STUB_IP_ADDRS="$(fixture ip-addrs/tailscale-and-bridges.txt)"

  run "$DECK" listen 4444

  assert_success
  refute_output --partial "172.17.0.1"     # docker0
  refute_output --partial "172.24.0.1"     # br-*
  refute_output --partial "192.168.122.1"  # virbr0
}

@test "no default route: first real local address is promoted, labelled as such" {
  export STUB_IP_ROUTE="noroute"
  export STUB_IP_ADDRS="$(fixture ip-addrs/single-homed.txt)"

  run "$DECK" listen 4444

  assert_success
  assert_output --partial "203.0.113.10   (no default route - first local address)"
}

@test "nothing detectable: placeholder, labelled honestly" {
  export STUB_IP_ROUTE="noroute"
  export STUB_IP_ADDRS="$(fixture ip-addrs/empty.txt)"

  run "$DECK" listen 4444

  assert_success
  assert_output --partial "<your-host-IP>   (could not detect one)"
}

@test "link-local (169.254) is not offered as a callback address" {
  export STUB_IP_ROUTE="noroute"
  export STUB_IP_ADDRS="$(fixture ip-addrs/link-local-only.txt)"

  run "$DECK" listen 4444

  assert_success
  refute_output --partial "169.254"
  assert_output --partial "(could not detect one)"
}

@test "macOS branch: utun (VPN/tailnet) kept, bridge/vmnet dropped" {
  export STUB_UNAME="Darwin"
  export STUB_ROUTE_IFACE="en0"
  export STUB_IFADDR="192.168.1.20"
  export STUB_IFCONFIG="$(fixture ifconfig/macos-utun-and-bridge.txt)"

  run "$DECK" listen 4444

  assert_success
  assert_output --partial "192.168.1.20   (host default route)"
  assert_output --partial "another address on this host         : 100.88.1.2"
  refute_output --partial "192.168.64.1"    # bridge100
  refute_output --partial "172.16.187.1"    # vmnet8
  refute_output --partial "127.0.0.1"
}

@test "still publishes the ports and hands off to docker compose" {
  export STUB_IP_ROUTE="1.1.1.1 via 203.0.113.1 dev enp1s0 src 203.0.113.10 uid 0"
  export STUB_IP_ADDRS="$(fixture ip-addrs/single-homed.txt)"

  run "$DECK" listen 4444 9001

  assert_success
  assert_called 'docker compose run --rm -p 4444:4444 -p 9001:9001 deck'
}
