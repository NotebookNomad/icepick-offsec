#!/usr/bin/env bats
# The half of the checklist no fixture can stand in for: a real tunnel.
#
# Dormant until you put a working config in vpn/. With one there it connects for
# real and checks the things that only a live server can answer - that the
# handshake completes, that lockdown-wan's endpoint rule lets the tunnel keep
# running after the policy flips to DROP, and that the SOCKS proxy still reaches
# through the lockdown.
#
# Every test connects in its own `--rm` container, so nothing here disturbs a
# session you already have open. It does put real traffic on your lab VPN.
#
#   ./tests/run.sh integration
#   ICEPICK_VPN=htb.ovpn ./tests/run.sh integration     # pick, when several

load '../test_helper/common'

setup() {
  command -v docker >/dev/null || skip "docker not installed"
  docker image inspect icepick-offsec:latest >/dev/null 2>&1 \
    || skip "icepick-offsec:latest not built - run ./deck build"

  CFG="${ICEPICK_VPN:-}"
  if [ -z "$CFG" ]; then
    local found=()
    while IFS= read -r f; do found+=("$(basename "$f")"); done < <(
      find "${PROJECT_ROOT}/vpn" -maxdepth 1 -type f -name '*.ovpn' 2>/dev/null | sort)
    case ${#found[@]} in
      0) skip "no .ovpn in vpn/ - drop one there to enable the live-tunnel tests" ;;
      1) CFG="${found[0]}" ;;
      *) skip "several configs in vpn/ - set ICEPICK_VPN=<name> to choose" ;;
    esac
  fi
  [ -f "${PROJECT_ROOT}/vpn/${CFG}" ] || skip "no such config: vpn/${CFG}"
  export CFG
}

# Connect for real, run a script body in the same netns, tear the container down.
# --socks is published on a high random port so a session you already have open
# on 1080 is not disturbed.
in_tunnel() {
  local port=$((20000 + RANDOM % 10000))
  docker compose -f "${PROJECT_ROOT}/docker-compose.yml" run --rm -T \
    -v "${PROJECT_ROOT}/scripts/lockdown-wan:/usr/local/bin/lockdown-wan:ro" \
    -p "127.0.0.1:${port}:${port}" -e "SOCKS=${port}" -e "OVPN=${CFG}" \
    deck bash -c "
      openvpn --config /root/vpn/${CFG} --daemon --log /tmp/openvpn.log
      for _ in \$(seq 1 40); do
        grep -q 'Initialization Sequence Completed' /tmp/openvpn.log 2>/dev/null && break
        sleep 1
      done
      $*"
}

@test "the tunnel actually comes up" {
  run in_tunnel 'ip -o -4 addr show tun0 | awk "{print \"TUN=\" \$4}"'
  assert_success
  assert_output --partial "TUN="
}

@test "lockdown-wan leaves the tunnel up after the policy flips to DROP" {
  # The endpoint allow-rule is the whole reason this does not strand you. No
  # synthetic fixture can show it working against a real server.
  run in_tunnel '
    lockdown-wan /root/vpn/'"${CFG}"' >/dev/null 2>&1
    sleep 5
    ip -o -4 addr show tun0 >/dev/null && echo "TUNNEL ALIVE" || echo "TUNNEL GONE"
    iptables -S OUTPUT | grep -q "^-P OUTPUT DROP" && echo "POLICY DROP"'
  assert_success
  assert_output --partial "TUNNEL ALIVE"
  assert_output --partial "POLICY DROP"
}

@test "the internet is unreachable once locked down, the tunnel is not" {
  run in_tunnel '
    gw=$(ip route | awk "/^default/{print \$3; exit}")
    lockdown-wan /root/vpn/'"${CFG}"' >/dev/null 2>&1
    curl -m 6 -s -o /dev/null https://example.com && echo "INTERNET REACHED" || echo "internet blocked"
    ping -c1 -W3 "$gw" >/dev/null 2>&1 && echo "GATEWAY REACHED" || echo "gateway blocked"
    ip route | grep -q tun0 && echo "tunnel routes present"'
  assert_success
  assert_output --partial "internet blocked"
  assert_output --partial "gateway blocked"
  assert_output --partial "tunnel routes present"
  refute_output --partial "INTERNET REACHED"
}

@test "the SOCKS proxy still relays through the lockdown" {
  # microsocks binds 0.0.0.0 inside the container and relays out tun0. If the
  # established-flow rule were below the gateway drop this would hang.
  run in_tunnel '
    microsocks -i 0.0.0.0 -p "$SOCKS" >/tmp/microsocks.log 2>&1 &
    sleep 1
    lockdown-wan /root/vpn/'"${CFG}"' >/dev/null 2>&1
    kill -0 %1 2>/dev/null && echo "PROXY ALIVE" || echo "PROXY DIED"
    curl -m 8 -s -o /dev/null --socks5 "127.0.0.1:$SOCKS" http://10.10.10.10 
    echo "relay-exit=$?"'
  assert_success
  assert_output --partial "PROXY ALIVE"
  # Whatever the lab answers, the proxy must not refuse the connection itself:
  # curl 7 is "could not connect to proxy", which is the failure being excluded.
  refute_output --partial "relay-exit=7"
}

@test "deck vpn picks this config up by name end to end" {
  run timeout 90 "${PROJECT_ROOT}/deck" vpn "$CFG" --socks 21080 </dev/null
  assert_output --partial "$CFG"
  refute_output --partial "no .ovpn in vpn/"
}
