# tests

`bats` suites for `deck` and the container-side scripts. The static and unit
layers use fake `docker`/`ip`/`openvpn`/… so there is **no Docker, no root, and
no network** — they finish in a couple of seconds. The integration layer needs a
built image.

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
run `integration`: that layer needs the ~10 GB image, which a GitHub runner
shouldn't build on every push. Run it locally after `./deck build`.

## Layout

| dir | needs | what it checks |
| --- | --- | --- |
| `static/` | `shellcheck`, `zsh`, `docker` (each skipped if absent) | `bash -n` / `zsh -n` on every script; `shellcheck -x --severity=warning`; `docker compose config` validates and still declares `NET_ADMIN` + `/dev/net/tun` |
| `unit/` | just `bash` | `deck listen` address detection; `deck vpn` flag parsing and config selection; `vpn-connect` messaging for a live vs down tunnel, the `--socks` note, and `--lockdown` fail-closed |
| `integration/` | `docker` + a built image (and, for `vpn.bats`, a real config in `vpn/`) | the image's contents (the Go tools, the headless gap, the `httpx` symlink, gf's patterns, GEF, the pwn toolchain), that `nmap` execs under its file capabilities, that `NET_ADMIN` + `/dev/net/tun` reach a running container, and both firewall scripts against real iptables |

`shellcheck` runs at `--severity=warning`: `deck` and `lockdown-wan` have two
deliberate `info`-level word-splits.

**Stubs** (`stubs/bin/`) are fake executables put ahead of the real ones by
`use_stubs`; each logs its argv to `$STUB_CALLLOG` and tests assert with
`assert_called` / `refute_called`. Behaviour is driven by env vars (`STUB_IP_ROUTE`,
`STUB_TUN`, `STUB_LOCKDOWN_RC`, … — see each stub's header). **Fixtures**
(`fixtures/`) are canned interface listings and **synthetic** OpenVPN configs
(structure only, no key material). `unit/vpn_connect.bats` writes `/tmp/*.log` at
fixed paths, so run it serially, not with `bats --jobs`.

## The stale-image trap

The scripts are `COPY`'d into the image, so a container runs whatever the last
`./deck build` captured — not what's in `scripts/`. A green integration run
against a stale image is the exact false pass this suite exists to prevent, and
editing a script doesn't rebuild anything. So `tests/run.sh` checksums `scripts/`
against the image's copies before the integration suite and **refuses to run** if
they differ, telling you to `./deck build`. (Building automatically would be
tidier and is a trap: the Dockerfile's `# syntax=` directive and the moving
`kalilinux/kali-rolling` base can turn a "quick" rebuild into tens of minutes or
an `apt` failure unrelated to your change.)

## The live-tunnel layer (manual)

`integration/vpn.bats` stays dormant until you put a working `.ovpn` in `vpn/`.
With one there it connects for real and checks what no fixture can: the handshake
completing, the tunnel **surviving** `lockdown-wan`'s policy flip, the internet
and host gateway being unreachable afterwards while the tunnel routes remain, and
the SOCKS proxy still relaying through the lockdown. Each test runs in its own
`--rm` container on a random port, but it does put real traffic on your lab VPN.

```sh
ICEPICK_VPN=htb.ovpn ./tests/run.sh integration        # pick, when several
ICEPICK_LAB_TARGET=10.129.75.4 ./tests/run.sh integration   # also prove a real relay
```

Without `ICEPICK_LAB_TARGET`, the proxy test can only show microsocks survived
the lockdown and still completes a SOCKS handshake (curl exit 7 = proxy died,
28/97 = proxy up but target silent, 0 = a real relay); point it at a running box
to get the last one. Still manual, because it needs two machines: a `./deck
shell` in host-side `tmux` surviving an SSH disconnect.
