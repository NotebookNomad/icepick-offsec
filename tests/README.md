# tests

`bats` suites for `deck` and the container-side scripts. The unit layer runs the
real scripts against fake `docker`/`ip`/`openvpn`/… so there is **no Docker, no
root, and no network** involved — it finishes in a couple of seconds.

## Running

```sh
git submodule update --init --recursive   # once: bats + bats-assert + bats-support
./tests/run.sh                            # static + unit (the default)
./tests/run.sh static                     # just the linters
./tests/run.sh unit
./tests/run.sh integration                # needs a built image; ~90s
./tests/run.sh all
```

CI runs `static unit` on every PR (`.github/workflows/tests.yml`). It does not
run `integration`: that layer needs the ~10 GB image, which is not something a
GitHub runner should build on every push. Run it locally after `./deck build`.

## Layout

| dir | needs | what it checks |
| --- | --- | --- |
| `static/` | `shellcheck`, `zsh`, `docker` (each skipped if absent) | `bash -n` / `zsh -n` on every script; `shellcheck -x --severity=warning`; `docker compose config` validates and still declares `NET_ADMIN` + `/dev/net/tun` |
| `integration/` | `docker` + a built `icepick-offsec:latest`, and for `vpn.bats` a real config in `vpn/` (each skipped if absent) | the image's contents (the Go tools, the headless gap, the `httpx` symlink, gf's patterns, GEF, the pwn toolchain), that `nmap` execs at all under its file capabilities, that `NET_ADMIN` and `/dev/net/tun` reach a running container, and both firewall scripts against real iptables |
| `unit/` | nothing but `bash` | `deck listen` address detection (default-route guess, the tailnet/other-address list, docker/bridge/link-local filtering, the fallback ladder, the macOS branch); `deck vpn` flag parsing → the args handed to `docker compose run`; `scripts/vpn-connect` messaging for a live vs unconnected tunnel, the `--socks` "WAITING" note, and `--lockdown` fail-closed |

`shellcheck` runs at `--severity=warning`: `deck` and `lockdown-wan` have two
deliberate `info`-level word-splits (`$addrs`, `for host in $(...)`).

### Stubs

`stubs/bin/` holds fake executables put ahead of the real ones on `PATH` by
`use_stubs`. Each appends its argv to `$STUB_CALLLOG`; tests assert with
`assert_called` / `refute_called`. Behaviour is driven by env vars the test
sets — `STUB_IP_ROUTE`, `STUB_IP_ADDRS`, `STUB_TUN`, `STUB_UNAME`,
`STUB_LOCKDOWN_RC`, … (see each stub's header).

`unit/vpn_connect.bats` writes `/tmp/openvpn.log` and `/tmp/microsocks.log` at
the fixed paths the real script uses — run it serially, not with `bats --jobs`.
Its `setup` clears those files and `skip`s if another user owns them, so it is
safe on a shared box but can't run two at once.

### Fixtures

`fixtures/ip-addrs/*` and `fixtures/ifconfig/*` are canned interface listings.
`fixtures/ovpn/*` are **synthetic** OpenVPN configs — structure only, no real
key material, not working configs.

### A trap the integration layer has to work around

The scripts are `COPY`'d into the image, so a container runs whatever
`./deck build` last captured, not what is in `scripts/`. `lockdown.bats`
therefore mounts the working-tree copies over the packaged ones — without that
it tests a stale artifact, and a mutation to `lockdown-wan` passes green.
`image.bats` keeps one test comparing the two by checksum, so drift is reported
rather than silently changing what the suite means. If it fails, rebuild.

`lockdown.bats` fakes the tunnel with `ip tuntap add dev tun0`, which is enough
to exercise every rule `lockdown-wan` writes. What it cannot show is a live
tunnel surviving the policy flip — see below.

## The live-tunnel layer

`integration/vpn.bats` is dormant until you put a working `.ovpn` in `vpn/`.
With one there it connects for real and covers what no fixture can: the
handshake completing, the tunnel **surviving** `lockdown-wan`'s policy flip (the
endpoint allow-rule is what keeps OpenVPN going once the policy is `DROP`), the
internet and the host gateway being unreachable afterwards while the tunnel
routes remain, and the SOCKS proxy still relaying through the lockdown — what
the established-flow rule above the gateway drop exists for.

Each test connects in its own `--rm` container on a random high port, so it will
not disturb a session you already have open, but it does put real traffic on
your lab VPN. With several configs present, name one:

```sh
ICEPICK_VPN=htb.ovpn ./tests/run.sh integration
```

Still manual, because it needs two machines: a `./deck shell` in host-side
`tmux` surviving an SSH disconnect.
