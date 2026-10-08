# Internals & design

Why the container is built the way it is. You don't need any of this to use the
toolkit — but if you're tempted to "harden" the compose file, or you maintain the
downstream autonomous image, read the relevant section first.

## What's in it

`kali-linux-headless` (1342 packages), plus 27 packages it leaves out, plus 14
tools that aren't packaged for Kali or Debian at all.

Most of the 27 are the measured gap, not a curation — headless ships no
ProjectDiscovery tools (`nuclei`, `httpx`, `subfinder`, `naabu`, `dnsx`) and no
debugger (`gdb`, `gdbserver`, `ltrace`, `strace`, `patchelf`, `checksec`,
`pwntools`). The rest fill it out: recon and content discovery (`assetfinder`,
`arjun`, `autorecon`, `enum4linux-ng`, `feroxbuster`), forensics and CTF
miscellany (`foremost`, `steghide`, `uro`, `name-that-hash`), and the plumbing
`deck` itself needs (`netcat-openbsd`, `iputils-ping`, `dnsutils`, `iptables`,
`openvpn` for `deck vpn`, `microsocks` for `deck vpn --socks`).

The 14 are built or wrapped in the Dockerfile. Eight are Go (`katana`,
`dalfox`, `gau`, `waybackurls`, `anew`, `unfurl`, `qsreplace`, `gf`), compiled in
a first stage so the toolchain never ships. `rustscan` is built with cargo,
which is dropped in the same layer for the same reason — there is no upstream
multiarch binary. `one_gadget` and `seccomp-tools` are gems. `angr` and
`ROPgadget` live in a venv at `/opt/pyenv`, kept off PEP-668 system python but
built `--system-site-packages` so the apt `pwntools` is visible from the same
interpreter; run them with `angr-python` and `ROPgadget`. `jwt_tool` is wrapped
as `jwt-analyzer`.

`gf` has 37 patterns baked in — tomnomnom's examples for grepping responses,
plus `1ndianl33t/Gf-Patterns` for vulnerable URL params (`ssrf`, `xss`, `sqli`,
`lfi`, `idor`...). `gf -list` shows them.

Wordlists aren't in the image — SecLists alone is 1.8 GB. `./deck wordlists`
puts SecLists, assetnote, PayloadsAllTheThings and `rockyou.txt` on a named
volume, reachable as `$WORDLISTS` inside the shell (`sl` cds into SecLists).

## Why it runs as root

Trimming capabilities breaks more than it protects. Verified, when this was
built the hardened way:

- **`cap_add` does nothing for a non-root user.** Docker puts added capabilities
  in the *bounding* set; `CapPrm`/`CapEff` stay zero for any uid != 0. So
  `NET_RAW` + `user: 1000` still means no raw sockets — no masscan, no `nmap -sS`.
- **`cap_drop: ALL` takes `CAP_DAC_OVERRIDE` from root**, which is what lets root
  ignore file permissions. Capability-stripped root couldn't write its own
  volumes — *less* privileged than an unprivileged user.
- **Kali's nmap ships with file capabilities**
  (`cap_net_bind_service,cap_net_admin,cap_net_raw`). The kernel refuses to
  `exec` a binary whose file caps aren't a subset of the container's bounding
  set, so nmap died before `main()` — including a plain `-sT`, as root.

What root costs is bounded: `CAP_SYS_ADMIN` isn't in Docker's default set, and
that's the capability nearly every container escape needs. `no-new-privileges`
and the default seccomp profile are on. How much an escape would cost you does
depend on the host: under Docker Desktop it lands in Docker's Linux VM, while on
a Linux Docker host it lands on the host kernel itself.

## Do not remove `NET_ADMIN`

`docker-compose.yml` grants `cap_add: [NET_ADMIN]`. It looks like something you
could trim for hardening. **It isn't.**

Three things need it, and the first is not obvious:

1. **nmap.** Because of the file capabilities above, nmap only execs if
   `NET_ADMIN` is in the bounding set. Drop it and every scan — including
   `-sT` as root — fails with `Operation not permitted` before `main()` runs.
   The error names no capability and looks like a network problem.
2. **`lockdown-lan`**, to write iptables rules.
3. **`openvpn`**, to configure the tun device.

Verified both ways: with Kali's file caps in place, nmap fails under Docker's
default capability set and succeeds with `NET_ADMIN` added.

## This image is another image's base

Nothing here runs an agent. There is no MCP server, no agent runtime, no exposed
port — `CMD` is a login shell and `./deck` is how you drive it. That is on
purpose: a second repo, `icepick-offsec-autonomous`, builds `FROM` this image
and adds the agent layer (HexStrike AI's MCP server) on top. This one stays
tool-only.

The cost of that split is a contract you can't see from the Dockerfile alone.
Some of what this image exposes is named for what HexStrike's probes invoke
rather than for what the tool calls itself, so a rename that looks like tidying
here breaks the overlay — and breaks it at *its* runtime, not at this image's
build, which is the worst place to find out.

**Load-bearing, and not obviously so:**

1. **The tag.** `icepick-offsec:latest`, in `docker-compose.yml`, is the string
   the overlay's `FROM` names.
2. **Five binaries, by exact name on `PATH`.** `jwt-analyzer` is the one to
   watch — it's `jwt_tool`, and the name shares nothing with the project's own,
   so it reads like a mistake. The others are `angr-python`, `ROPgadget`,
   `rustscan`, and `httpx` (a symlink to Kali's `httpx-toolkit`, because
   `python3-httpx` owns `/usr/bin/httpx`).
3. **One interpreter for the pwn trio.** `/opt/pyenv/bin/python3` has to keep
   `pwn`, `angr` and `ropgadget` importable together — that's the whole reason
   the venv is built `--system-site-packages`. Splitting them breaks the overlay
   even if every name above survives.
4. **Four apt tools it shares**: `autorecon`, `enum4linux-ng`, `feroxbuster`,
   and `openvpn` — which also backs `deck vpn`, so only that last one has a
   second reason to stay.

`tests/integration/image.bats` guards the names. It isn't run in CI — the layer
needs the ~10 GB image — so it's a local gate: `./deck build`, then
`./tests/run.sh integration`.

## Limits

- **A container is not a VM.** It stops accidents and ordinary malware, not a
  kernel exploit written to break out. For hostile samples use a disposable VM
  or gVisor (`--runtime=runsc`).
- **It can reach whatever the host can.** Your router and NAS at home; your
  provider's internal network on a VPS. `lockdown-lan` blocks RFC1918 from
  inside; rules are per container, so re-run it each session.
- **Scanning out of a VPS is a provider question.** Lab VPN traffic is one
  encrypted flow and nobody minds. A `nuclei` sweep leaving a rented box reads
  as abuse to automated systems — check the AUP before you point recon at
  bounty scope from one.
- **`workspace/` is a real host directory** — the one path where container
  output touches the host.
- **`@latest` in the Go stage** means builds aren't reproducible. Deliberate;
  pin them if you disagree.
- **Scope is your job.** `scope.txt` and `inscope` are a convenience, not a
  control.

## Gotchas

Longer mechanism notes that used to live inline in the scripts. The code keeps a
one-line summary and points here.

### `vpn-connect`: the SOCKS proxy starts whether or not `tun0` is up

`microsocks` is a plain TCP relay — it routes per connection, not at startup, so
it begins working the moment a tunnel appears. That's why `vpn-connect` starts it
unconditionally instead of gating on a live `tun0`. Gating it would break the
hand-connect path for auth-user-pass configs (see
[walkthrough](walkthrough.md#when-something-doesnt-work)): by the time you've run
`openvpn` by hand in the shell, there'd be no proxy left to use, and `deck` has
already published the port for this container. A tunnel that finishes after the
20-second wait, and a `dev tap` config that comes up as `tap0` rather than
`tun0`, are the same case. So it starts the proxy and says plainly when it has
nothing to reach yet.

### `zshrc`: lab hosts resolve last-mention-wins

`hosts add` only ever appends to `workspace/hosts.thm`, and the collision is
settled when `/etc/hosts` is written, not when a line is added. A room hands you
a new IP each time you start it, so the file accumulates; keeping the *first*
sighting while walking the lines backwards means the most recent entry for a
name wins in one pass. Two payoffs: the file stays append-only, so nothing you
hand-edit into it (notes, comments) can be destroyed, and a sibling vhost stays
alive when a later line re-points only one of the names it shares a line with.
Names are lowercased (resolution is case-insensitive) and `\r` is stripped (the
file gets edited from the host side). `hosts load` and shell startup run the
exact same pass.
