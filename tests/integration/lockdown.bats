#!/usr/bin/env bats
# The two firewall scripts, against real iptables in a real container. Nothing
# here is reachable from the unit layer: it needs NET_ADMIN, a tun device and a
# kernel that will actually install the rules.
#
# No VPN is involved. tun0 is created with `ip tuntap`, which is enough to
# exercise every rule lockdown-wan writes - what it cannot prove is that a live
# tunnel survives the policy flip. That check needs a real .ovpn and stays in
# the manual list in tests/README.md.

load '../test_helper/common'

setup() {
  command -v docker >/dev/null || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose v2 not available"
  docker image inspect icepick-offsec:latest >/dev/null 2>&1 \
    || skip "icepick-offsec:latest not built - run ./deck build"
}

# The scripts are COPY'd into the image, so a container runs whatever
# `./deck build` last captured. Mount the working-tree copies over them: without
# this the suite tests a stale artifact, and a mutation to scripts/lockdown-wan
# sails straight through a green run. image.bats covers the packaged copies.
dcrun() {
  docker compose -f "${PROJECT_ROOT}/docker-compose.yml" run --rm -T \
    -v "${PROJECT_ROOT}/scripts/lockdown-wan:/usr/local/bin/lockdown-wan:ro" \
    -v "${PROJECT_ROOT}/scripts/lockdown-lan:/usr/local/bin/lockdown-lan:ro" \
    "$@"
}

# Run a script body in a container that already has a tun0, with an .ovpn
# fixture mounted at /tmp/lab.ovpn. Rules die with the container.
with_tun() {
  local ovpn="${1:?fixture}"; shift
  dcrun -v "$(fixture "ovpn/$ovpn"):/tmp/lab.ovpn:ro" deck bash -c "
    ip tuntap add dev tun0 mode tun
    ip link set tun0 up
    ip addr add 10.10.14.5/24 dev tun0
    $*"
}

@test "lockdown-wan refuses without tun0, and installs nothing" {
  run dcrun deck bash -c 'lockdown-wan; echo "rc=$?"; iptables -S OUTPUT | head -1'
  assert_output --partial "no tun0"
  assert_output --partial "rc=1"
  # Fail closed means fail *clean*: the default policy must be untouched.
  assert_output --partial "-P OUTPUT ACCEPT"
}

@test "lockdown-wan sets a default-deny OUTPUT policy" {
  run with_tun numeric-remote.ovpn 'lockdown-wan /tmp/lab.ovpn >/dev/null 2>&1; iptables -S OUTPUT'
  assert_success
  assert_output --partial "-P OUTPUT DROP"
}

@test "loopback, tun0 and the VPN endpoint are permitted" {
  run with_tun numeric-remote.ovpn 'lockdown-wan /tmp/lab.ovpn >/dev/null 2>&1; iptables -S OUTPUT'
  assert_success
  assert_output --partial "-A OUTPUT -o lo -j ACCEPT"
  assert_output --partial "-o tun0 -j ACCEPT"
  assert_output --partial "-d 203.0.113.77/32 -j ACCEPT"
}

@test "the host gateway is dropped, not swept up by the bridge subnet allow" {
  run with_tun numeric-remote.ovpn '
    gw=$(ip route show default dev eth0 | awk "{print \$3; exit}")
    lockdown-wan /tmp/lab.ovpn >/dev/null 2>&1
    iptables -S OUTPUT | grep -- "-d ${gw}/32" || echo "NO GATEWAY RULE"'
  assert_success
  assert_output --partial "-j DROP"
  refute_output --partial "NO GATEWAY RULE"
}

@test "the established-flow rule precedes the gateway drop" {
  # Load-bearing ordering. A published port's replies travel back toward the
  # gateway as an established flow, so reversing these two kills the --socks
  # proxy - and the symptom is a browser that hangs, not an error.
  run with_tun numeric-remote.ovpn '
    lockdown-wan /tmp/lab.ovpn >/dev/null 2>&1
    iptables -S OUTPUT | awk "
      /conntrack/ && !c { c = NR }
      /-j DROP/ && \$0 ~ /-d / && !g { g = NR }
      END { if (c && g && c < g) print \"ORDER OK\"; else print \"ORDER WRONG c=\" c \" g=\" g }"'
  assert_success
  assert_output --partial "ORDER OK"
}

@test "IPv6 egress is dropped too" {
  # An IPv6-capable host would otherwise keep a second way out behind a
  # firewall that looks complete.
  run with_tun numeric-remote.ovpn 'lockdown-wan /tmp/lab.ovpn >/dev/null 2>&1; ip6tables -S OUTPUT'
  assert_success
  assert_output --partial "-P OUTPUT DROP"
}

@test "the resolver is emptied - the leak iptables cannot close" {
  # Docker's resolver at 127.0.0.11 is reached over loopback but forwards
  # upstream from outside this netns, so DNS never traverses OUTPUT.
  run with_tun numeric-remote.ovpn '
    lockdown-wan /tmp/lab.ovpn >/dev/null 2>&1
    echo "nameservers=$(grep -c nameserver /etc/resolv.conf || true)"'
  assert_success
  # Marker rather than an exact match: `docker compose run` writes its progress
  # lines to stderr, and bats folds those into $output.
  assert_output --partial "nameservers=0"
}

@test "lab names still resolve from /etc/hosts after lockdown" {
  run with_tun numeric-remote.ovpn '
    echo "10.10.11.7 blog.thm" >> /etc/hosts
    lockdown-wan /tmp/lab.ovpn >/dev/null 2>&1
    getent hosts blog.thm'
  assert_success
  assert_output --partial "10.10.11.7"
}

@test "KEEP_DNS=1 leaves the resolver alone and says so" {
  run with_tun numeric-remote.ovpn '
    KEEP_DNS=1 lockdown-wan /tmp/lab.ovpn 2>&1 | grep -i "keep_dns"
    echo "nameservers=$(grep -c nameserver /etc/resolv.conf)"'
  assert_success
  assert_output --partial "nameservers=1"
  # The warning itself, not a count of it: a grep -c prints 0 and still exits
  # into a passing test if the message ever goes away.
  assert_output --partial "name lookups still leak"
}

@test "an unresolvable remote is reported, not silently skipped" {
  # cert-only.ovpn points at lab.example.net, which does not resolve, so no
  # endpoint rule can be installed. Silence there is the dangerous case: the
  # tunnel runs on its established flow until the first re-handshake, then
  # strands. The warning is the whole point of the test.
  run with_tun cert-only.ovpn 'lockdown-wan /tmp/lab.ovpn 2>&1'
  assert_success
  assert_output --partial "lab.example.net did not resolve"
  assert_output --partial "cannot re-handshake"
  assert_output --partial "Egress locked to the VPN"
}

@test "lockdown-lan permits the container's own subnet and gateway first" {
  # Its inverse: blocks RFC1918 but must not sever the route it arrived on.
  run dcrun deck bash -c 'lockdown-lan 2>&1; iptables -S OUTPUT'
  assert_success
  assert_output --partial "permitting own subnet"
  assert_output --partial "10.0.0.0/8 -j REJECT"
  assert_output --partial "192.168.0.0/16 -j REJECT"
}

@test "lockdown-lan actually blocks a private destination" {
  run dcrun deck bash -c '
    lockdown-lan >/dev/null 2>&1
    curl -m 3 -s -o /dev/null http://192.168.201.9 && echo REACHED || echo blocked'
  assert_success
  assert_output --partial "blocked"
}
