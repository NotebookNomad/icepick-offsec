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
```

CI runs `static unit` on every PR (`.github/workflows/tests.yml`).

## Layout

| dir | needs | what it checks |
| --- | --- | --- |
| `static/` | `shellcheck`, `zsh`, `docker` (each skipped if absent) | `bash -n` / `zsh -n` on every script; `shellcheck -x --severity=warning`; `docker compose config` validates and still declares `NET_ADMIN` + `/dev/net/tun` |
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

### Fixtures

`fixtures/ip-addrs/*` and `fixtures/ifconfig/*` are canned interface listings.
`fixtures/ovpn/*` are **synthetic** OpenVPN configs — structure only, no real
key material, not working configs.

## Not covered here (needs a built image / a real tunnel)

Run these by hand against a freshly built image:

- `./deck build` succeeds; `./deck run sh -c 'which katana dalfox gau anew gf nuclei httpx subfinder'`
- `./deck run nmap -sT -p80 scanme.nmap.org` — the NET_ADMIN / file-capabilities interaction
- `./deck run zsh -lic 'whereami'` shows `cap_net_admin`
- `python3 -c 'import pwn'`, `checksec`, `one_gadget`, `seccomp-tools` in the image
- `lockdown-lan` / `lockdown-wan` actually installing iptables rules
- a real HTB/THM `.ovpn` (+ credentials, never committed): `tun0` comes up, `deck vpn --socks` binds `127.0.0.1` only, `deck vpn --lockdown` blocks non-tunnel egress while the tunnel and `hosts add` names still work
- a `./deck shell` in host-side `tmux` surviving an SSH disconnect
