#!/usr/bin/env bats
# scripts/vpn-connect: what it reports for a live vs unconnected tunnel, the
# --socks "WAITING" note, and the --lockdown fail-closed path. Run serially -
# vpn-connect writes /tmp/openvpn.log and /tmp/microsocks.log at fixed paths.

load '../test_helper/common'

VC="${PROJECT_ROOT}/scripts/vpn-connect"

setup() {
  use_stubs
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/workspace"
  cp "$(fixture ovpn/cert-only.ovpn)" "${HOME}/workspace/cert-only.ovpn"
  export OVPN="cert-only.ovpn"
  TUN_LINE="3: tun0    inet 10.10.15.5/23 scope global tun0\\       valid_lft forever preferred_lft forever"

  # vpn-connect and the openvpn stub write these fixed paths. If another user
  # owns them we can neither truncate nor trust the contents - a stale success
  # line would give a false "VPN up:" - so bail rather than pass wrongly.
  for f in /tmp/openvpn.log /tmp/microsocks.log; do
    if [ -e "$f" ] && [ ! -O "$f" ]; then
      skip "$f exists and is owned by another user - run in an isolated /tmp"
    fi
    rm -f "$f"
  done
}

@test "tunnel down: says so, points at the manual connect, still opens a shell" {
  run "$VC"
  assert_success
  assert_output --partial "tun0 not up yet"
  assert_output --partial "manual connect: openvpn --config ${HOME}/workspace/cert-only.ovpn"
  refute_output --partial "VPN up:"
  refute_output --partial "WAITING"
  assert_called '^zsh -l'
}

@test "tunnel down + --socks: proxy starts but is flagged as reaching nothing" {
  export SOCKS=1080
  run "$VC"
  assert_success
  assert_output --partial "tun0 not up yet"
  assert_output --partial "SOCKS5 up on the host at 127.0.0.1:1080"
  assert_output --partial "WAITING : no tun0, so the proxy reaches nothing yet."
  assert_called 'microsocks -i 0\.0\.0\.0 -p 1080'
}

@test "tunnel up: reports the tun0 address, no WAITING note" {
  export STUB_TUN="$TUN_LINE"
  run "$VC"
  assert_success
  assert_output --partial "VPN up: 10.10.15.5/23"
  refute_output --partial "tun0 not up yet"
  refute_output --partial "WAITING"
  assert_called '^zsh -l'
}

@test "tunnel up + --socks: proxy up, no WAITING note" {
  export STUB_TUN="$TUN_LINE"
  export SOCKS=1080
  run "$VC"
  assert_success
  assert_output --partial "VPN up: 10.10.15.5/23"
  assert_output --partial "SOCKS5 up on the host at 127.0.0.1:1080"
  refute_output --partial "WAITING"
  assert_called 'microsocks -i 0\.0\.0\.0 -p 1080'
}

@test "--lockdown: calls lockdown-wan with the config, then hands over the shell" {
  export STUB_TUN="$TUN_LINE"
  export EGRESS_FIREWALL=on
  run "$VC"
  assert_success
  assert_called "lockdown-wan ${HOME}/workspace/cert-only\\.ovpn"
  assert_called '^zsh -l'
}

@test "--lockdown fail-closed: lockdown-wan error aborts, no shell, no proxy" {
  export STUB_TUN="$TUN_LINE"
  export EGRESS_FIREWALL=on
  export SOCKS=1080
  export STUB_LOCKDOWN_RC=1
  run "$VC"
  assert_failure
  assert_output --partial "egress lockdown failed"
  assert_output --partial "Reconnect without --lockdown"
  refute_called '^zsh '
  refute_called 'microsocks'
}
