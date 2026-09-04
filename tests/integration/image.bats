#!/usr/bin/env bats
# Checks that need the real ~10 GB image: what actually got installed, and
# whether the capability plumbing survives a real container start. The unit
# layer replaces docker with a stub, so none of this is reachable there.
#
# Skipped whole when the image is absent - build it with ./deck build.
# Not run in CI: a 10 GB image is not something a GitHub runner should build.

load '../test_helper/common'

setup() {
  command -v docker >/dev/null || skip "docker not installed"
  docker compose version >/dev/null 2>&1 || skip "docker compose v2 not available"
  docker image inspect icepick-offsec:latest >/dev/null 2>&1 \
    || skip "icepick-offsec:latest not built - run ./deck build"
}

# Run in a throwaway container off the repo's own compose file, so the project
# name (and therefore the volumes) match what deck uses rather than spawning a
# parallel set.
dcrun() { docker compose -f "${PROJECT_ROOT}/docker-compose.yml" run --rm -T "$@"; }

@test "the 8 Go tools Kali does not package are on PATH" {
  run dcrun deck sh -c 'command -v katana dalfox gau waybackurls anew unfurl qsreplace gf'
  assert_success
}

@test "the toolset kali-linux-headless leaves out is installed" {
  run dcrun deck sh -c 'command -v nuclei httpx subfinder naabu dnsx arjun gdb strace checksec microsocks'
  assert_success
}

@test "httpx is projectdiscovery's, not python3-httpx" {
  # Kali ships it as httpx-toolkit because python3-httpx owns /usr/bin/httpx;
  # the Dockerfile symlinks it. A dangling link would still satisfy `command -v`.
  run dcrun deck sh -c 'readlink -f "$(command -v httpx)"'
  assert_success
  assert_output --partial "/usr/bin/httpx-toolkit"
}

@test "nmap execs at all, despite its file capabilities" {
  # The regression this guards: Kali's nmap carries cap_net_admin as a *file*
  # capability, and the kernel refuses to exec a binary whose file caps exceed
  # the container's bounding set. Without NET_ADMIN this fails before main()
  # with "Operation not permitted", which reads as a network fault, not a
  # capability one.
  run dcrun deck nmap --version
  assert_success
}

@test "nmap completes a scan as root" {
  # Loopback on purpose: a test suite should not put packets on the internet.
  # -sT still exercises the exec path the file-capabilities bug broke.
  run dcrun deck nmap -sT -Pn -p 22,80 127.0.0.1
  assert_success
  assert_output --partial "scanned in"
}

@test "NET_ADMIN reaches the container's effective set" {
  run dcrun deck sh -c 'capsh --decode=$(grep ^CapEff /proc/self/status | cut -f2)'
  assert_success
  assert_output --partial "cap_net_admin"
}

@test "the tun device is present for openvpn" {
  run dcrun deck test -c /dev/net/tun
  assert_success
}

@test "the pwn toolchain is importable and runnable" {
  run dcrun deck sh -c 'python3 -c "import pwn" && checksec --version && one_gadget --version && seccomp-tools --version'
  assert_success
}

@test "GEF is wired into gdb's system-wide init" {
  run dcrun deck sh -c 'test -f /opt/gef.py && grep -q gef /etc/gdb/gdbinit'
  assert_success
}

@test "gf's pattern set is baked into the image" {
  # On a volume these would be lost by `run --rm`; the Dockerfile bakes them in.
  run dcrun deck sh -c 'gf -list | tr "\n" " "'
  assert_success
  assert_output --partial "ssrf"
  assert_output --partial "xss"
  assert_output --partial "sqli"
}

@test "the toolkit's own scripts are installed and executable" {
  run dcrun deck sh -c 'for s in fetch-wordlists lockdown-lan lockdown-wan vpn-connect; do
                          test -x "/usr/local/bin/$s" || { echo "missing: $s"; exit 1; }
                        done'
  assert_success
}

@test "the packaged scripts match the working tree" {
  # Everything else in this file describes the image as built. If the scripts in
  # it are older than scripts/, that gap is worth knowing about explicitly:
  # lockdown.bats mounts the working-tree copies precisely so it does not test a
  # stale artifact, and this is what says the two have drifted. Rebuild to clear.
  for s in fetch-wordlists lockdown-lan lockdown-wan vpn-connect; do
    tree_sum=$(shasum "${PROJECT_ROOT}/scripts/$s" | awk '{print $1}')
    img_sum=$(dcrun deck shasum "/usr/local/bin/$s" | awk '{print $1}' | tr -d '\r')
    [ "$tree_sum" = "$img_sum" ] || {
      echo "image is stale for scripts/$s - run ./deck build"
      echo "  tree:  $tree_sum"
      echo "  image: $img_sum"
      return 1
    }
  done
}

@test "whereami reports the capability and the workspace mount" {
  run dcrun deck zsh -lic 'whereami'
  assert_success
  assert_output --partial "cap_net_admin"
  assert_output --partial "/root/workspace"
}
