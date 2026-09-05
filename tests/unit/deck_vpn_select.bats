#!/usr/bin/env bats
# Which config `deck vpn` connects with: the vpn/ directory, the auto-pick, the
# menu, and the paths that must never launch a container.

load '../test_helper/common'

setup() {
  use_stubs
  sandbox_deck
  DECK="$PWD/deck"
}

# Put a fixture in the sandbox's vpn/ under an arbitrary name.
drop() { cp "$(fixture "ovpn/$1")" "$PWD/vpn/$2"; }

@test "empty vpn/: says where to put a config, launches nothing" {
  run "$DECK" vpn
  assert_failure
  assert_output --partial "no .ovpn in vpn/"
  assert_output --partial "tryhackme.com/access"
  refute_called '^docker '
}

@test "exactly one config: used without being named" {
  drop cert-only.ovpn lab.ovpn
  run "$DECK" vpn
  assert_success
  assert_output --partial "using vpn/lab.ovpn"
  assert_called 'OVPN=lab\.ovpn'
}

@test "several configs, nothing to prompt: lists them, launches nothing" {
  # A menu written to a pipe would block forever waiting on an answer, so the
  # non-interactive path has to be a listing, not a question.
  drop cert-only.ovpn lab.ovpn
  drop auth-user-pass.ovpn htb.ovpn
  run "$DECK" vpn
  assert_failure
  assert_output --partial "several configs in vpn/"
  assert_output --partial "./deck vpn htb.ovpn"
  assert_output --partial "./deck vpn lab.ovpn"
  refute_called '^docker '
}

@test "a bare name selects from vpn/ without a prompt" {
  drop cert-only.ovpn lab.ovpn
  drop auth-user-pass.ovpn htb.ovpn
  run "$DECK" vpn htb.ovpn
  assert_success
  assert_called 'OVPN=htb\.ovpn'
}

@test "a path outside the repo is copied into vpn/" {
  run "$DECK" vpn "$(fixture ovpn/cert-only.ovpn)"
  assert_success
  [ -f "$PWD/vpn/cert-only.ovpn" ]
  assert_called 'OVPN=cert-only\.ovpn'
}

@test "a config already in vpn/ is not copied over itself" {
  drop cert-only.ovpn lab.ovpn
  local before; before=$(shasum "$PWD/vpn/lab.ovpn" | awk '{print $1}')
  run "$DECK" vpn "$PWD/vpn/lab.ovpn"
  assert_success
  [ "$(shasum "$PWD/vpn/lab.ovpn" | awk '{print $1}')" = "$before" ]
}

@test "a named config that does not exist: error, launches nothing" {
  drop cert-only.ovpn lab.ovpn
  run "$DECK" vpn nope.ovpn
  assert_failure
  assert_output --partial "no such file: nope.ovpn"
  refute_called '^docker '
}

@test "non-.ovpn files in vpn/ are ignored by the auto-pick" {
  # Credentials for an auth-user-pass config live here too; they are not configs.
  drop cert-only.ovpn lab.ovpn
  echo "user"  > "$PWD/vpn/creds.txt"
  printf 'x\n' > "$PWD/vpn/notes.md"
  run "$DECK" vpn
  assert_success
  assert_output --partial "using vpn/lab.ovpn"
}

# --- the interactive menu, driven through a real pty ------------------------
# bats gives the script a pipe, so `[ -t 0 ]` is false and the menu never runs.
# expect supplies the terminal that makes this path reachable at all.

# expect inherits PATH (stubs first), HOME and STUB_CALLLOG from bats, so the
# spawned deck behaves exactly as it does in the tests above - only now with a
# terminal on stdin. Passing them as arguments does not work: with -c, a
# trailing argument is read as a script file, not as $argv.
menu() {
  expect -c "
    set timeout 10
    spawn -noecho bash \"$DECK\" vpn
    expect \"choose \"
    send \"$1\r\"
    expect eof
  " 2>&1 | tr -d '\r'
}

@test "menu: choosing a number connects with that config" {
  command -v expect >/dev/null || skip "expect not installed"
  drop cert-only.ovpn lab.ovpn
  drop auth-user-pass.ovpn htb.ovpn
  run menu 1
  assert_output --partial "1) htb.ovpn"
  assert_output --partial "2) lab.ovpn"
  assert_output --partial "0) none - cancel"
  assert_called 'OVPN=htb\.ovpn'
}

@test "menu: 0 cancels and launches nothing" {
  command -v expect >/dev/null || skip "expect not installed"
  drop cert-only.ovpn lab.ovpn
  drop auth-user-pass.ovpn htb.ovpn
  run menu 0
  assert_output --partial "cancelled"
  refute_called '^docker '
}

@test "menu: a number out of range is refused, not clamped" {
  command -v expect >/dev/null || skip "expect not installed"
  drop cert-only.ovpn lab.ovpn
  drop auth-user-pass.ovpn htb.ovpn
  run menu 9
  assert_output --partial "out of range: 9"
  refute_called '^docker '
}

@test "menu: a non-number is refused" {
  command -v expect >/dev/null || skip "expect not installed"
  drop cert-only.ovpn lab.ovpn
  drop auth-user-pass.ovpn htb.ovpn
  run menu x
  assert_output --partial "not a number: x"
  refute_called '^docker '
}
