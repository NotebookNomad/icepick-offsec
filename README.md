# icepick-offsec

An offensive-security toolkit — a Kali container for authorized bug bounty work
and CTF exercises. The name nods to cyberpunk ICE (Intrusion Countermeasures
Electronics): an icepick breaks it. You drive it with `./deck`.

```bash
./deck build          # ~10 GB, 20-30 min first time
./deck wordlists      # once - SecLists etc. onto a shared volume
./deck shell          # you're in
```

## Requirements

**Tested only on Apple Silicon (ARM64) macOS with Docker Desktop.** The image
builds for arm64 (GEF and the Go tools are chosen for it), and the networking
model throughout — the Linux VM, `host.docker.internal`, LAN reachability, the
Burp and reverse-shell notes — assumes Docker Desktop's VM. It may work on Intel
macOS or a Linux Docker host with adjustments, but neither is tested or
supported.

## Usage

```
./deck shell              interactive shell
./deck listen [ports...]  shell with listener ports published to the LAN
./deck vpn <file.ovpn>    connect an HTB/THM VPN, then drop into a shell
./deck run <cmd...>       one-shot command, no shell
./deck status             what's running
./deck stop               stop everything
./deck clean --volumes    also drop wordlists + tool config (prompts first)
```

## Reverse shells and callbacks

A normal container publishes no ports, so a listener started inside it binds to
the private bridge IP and nothing off-host can reach it. Where the callback
needs to land depends on where the target is:

- **HTB / THM** — `./deck vpn lab.ovpn` connects and drops you in a shell.
  `openvpn` creates `tun0`, a routable address on the target's own network, so
  `nc -lvnp 4444` works with no publishing. Put your `tun0` IP (`ip addr show tun0`) in the
  payload.
- **A host on your LAN** — `./deck listen` publishes ports (default
  `4444 8000 9001 443`, or pass your own) to the host, and prints the LAN IP to
  aim callbacks at. Those ports are open to your whole LAN until you exit.
- **The public internet** — neither helps; the host is behind your router's NAT.
  Use a VPS or a tunnel (ngrok, SSH reverse tunnel) as the redirector.

`workspace/` on the host is mounted at `~/workspace`. It's the only shared path
— everything else dies with the container. It's gitignored, since it holds
loot, notes and scope files.

In the shell: `whereami` shows user/caps/egress, `lockdown-lan` blocks your LAN,
`inscope` reads `workspace/scope.txt`, `burp on` proxies through Burp.

## Burp Suite

Burp runs natively on the host; the container proxies into it. That keeps the
image lean and the UI fast, and your CLI recon lands in Burp's sitemap.

One-time setup — in Burp, **Proxy > Proxy settings > Add** a listener bound to
**All interfaces** on 8080. The default `127.0.0.1` listener is not reachable
from a container.

```bash
./deck shell
burp on            # exports http(s)_proxy -> host.docker.internal:8080
burp cert          # fetch + trust Burp's CA, so TLS verifies
burp               # show current state
burp off

katana -u https://target.com -proxy $BURP_PROXY
nuclei -list live.txt -proxy $BURP_PROXY
```

`burp cert` saves the CA to `workspace/.burp-ca.der` and re-trusts it
automatically in every later session, since the container itself is disposable.
Override the location with `BURP_HOST` / `BURP_PORT` if your listener differs.

## What's in it

`kali-linux-headless` (1342 packages), plus 22 tools it leaves out, plus 8 built
from source.

The 22 are the measured gap, not a curation — headless ships no ProjectDiscovery
tools (`nuclei`, `httpx`, `subfinder`, `naabu`, `dnsx`) and no debugger (`gdb`,
`strace`, `checksec`, `pwntools`). The 8 (`katana`, `dalfox`, `gau`,
`waybackurls`, `anew`, `unfurl`, `qsreplace`, `gf`) aren't in Kali's repo at all.

`gf` has 37 patterns baked in — tomnomnom's examples for grepping responses,
plus `1ndianl33t/Gf-Patterns` for vulnerable URL params (`ssrf`, `xss`, `sqli`,
`lfi`, `idor`...). `gf -list` shows them.

Wordlists aren't in the image — SecLists alone is 1.8 GB. `./deck wordlists`
puts SecLists, assetnote and PayloadsAllTheThings on a named volume.

## Recipes

```bash
./deck run nuclei -u https://target.example.com     # one-shot, no shell

./deck shell
subfinder -d target.com -silent | httpx -silent | anew live.txt
katana -list live.txt -silent | gau | uro | anew urls.txt
nuclei -list live.txt -severity medium,high,critical
gf ssrf < urls.txt | qsreplace 'http://your-collab' | httpx -silent

tmux new -s scan          # survives your terminal; C-a d to detach

# CTF binary
cp ./challenge ./workspace/ && ./deck shell
checksec --file=challenge && gdb ./challenge       # GEF preloaded

# HTB / THM - stages the config, connects, drops you in a shell on the VPN
./deck vpn ~/Downloads/lab.ovpn
ip addr show tun0          # your VPN IP, for reverse-shell callbacks
```

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

What root costs is bounded: `CAP_SYS_ADMIN` isn't in Docker's default set, and
that's the capability nearly every container escape needs. `no-new-privileges`
and the default seccomp profile are on. On macOS an escape lands in Docker's
Linux VM, not the host.

## Limits

- **A container is not a VM.** It stops accidents and ordinary malware, not a
  kernel exploit written to break out. For hostile samples use a disposable VM
  or gVisor (`--runtime=runsc`).
- **It can reach your LAN.** Your router and NAS are as reachable as the
  internet. `lockdown-lan` blocks RFC1918 from inside; rules are per container,
  so re-run it each session.
- **`workspace/` is a real host directory** — the one path where container
  output touches the host.
- **`@latest` in the Go stage** means builds aren't reproducible. Deliberate;
  pin them if you disagree.
- **Scope is your job.** `scope.txt` and `inscope` are a convenience, not a
  control.

## Layout

```
Dockerfile              two-stage: Go tools, then Kali runtime
docker-compose.yml      the container and its isolation settings
deck                    build / shell / run / wordlists / clean
config/                 zshrc, tmux.conf
scripts/                fetch-wordlists, lockdown-lan, vpn-connect
workspace/              shared with the host
```

---

For authorized testing only — programs you're enrolled in, CTFs you're playing,
systems you own. The isolation here protects *you* from the tools and the
targets; it confers no authorization to point them at anyone.
