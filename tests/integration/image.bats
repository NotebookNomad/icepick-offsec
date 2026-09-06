#!/usr/bin/env bats
# Checks that need the real ~10 GB image: what actually got installed, and
# whether the capability plumbing survives a real container start. The unit
# layer replaces docker with a stub, so none of this is reachable there.
#
# Skipped whole when the image is absent - build it with ./deck build.
# Not run in CI: a 10 GB image is not something a GitHub runner should build.

load '../test_helper/common'

setup() { require_image; }

# Run in a throwaway container off the repo's own compose file, so the project
# name (and therefore the volumes) match what deck uses rather than spawning a
# parallel set.
dcrun() { compose_run "$@"; }

@test "the 8 Go tools Kali does not package are on PATH" {
  run dcrun deck sh -c 'command -v katana dalfox gau waybackurls anew unfurl qsreplace gf'
  assert_success
}

@test "the toolset kali-linux-headless leaves out is installed" {
  run dcrun deck sh -c 'command -v nuclei httpx subfinder naabu dnsx arjun gdb strace checksec microsocks \
                                   autorecon enum4linux-ng feroxbuster openvpn'
  assert_success
}

@test "the source-built extras shared with the autonomous overlay are on PATH" {
  # rustscan (cargo), jwt-analyzer (jwt_tool wrapper) and ROPgadget (venv) are
  # not apt packages; the Dockerfile builds/wraps each. HexStrike calls them by
  # these exact names, so a rename here would silently break the autonomous rig.
  run dcrun deck sh -c 'command -v rustscan jwt-analyzer ROPgadget'
  assert_success
}

@test "angr and ROPgadget are importable from the /opt/pyenv interpreter" {
  # angr is not system python (PEP-668); it lives in /opt/pyenv, which is built
  # --system-site-packages so pwntools is visible from the same interpreter.
  run dcrun deck /opt/pyenv/bin/python3 -c 'import angr, ropgadget, pwn'
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
  # Globbed, not listed - tests/static/*.bats glob scripts/* for the same
  # reason, so a newly added script cannot quietly skip the gate.
  local names; names=$(cd "${PROJECT_ROOT}/scripts" && echo *)
  run dcrun deck sh -c 'for s in '"$names"'; do
                          test -x "/usr/local/bin/$s" || { echo "missing: $s"; exit 1; }
                        done'
  assert_success
}

@test "whereami reports the capability and the workspace mount" {
  run dcrun deck zsh -lic 'whereami'
  assert_success
  assert_output --partial "cap_net_admin"
  assert_output --partial "/root/workspace"
}
