# icepick-offsec

A Kali container for authorized bug bounty work and CTF labs. One build, one
command to get in, and nothing installed on your Mac. The name nods to cyberpunk
ICE (Intrusion Countermeasures Electronics): an icepick breaks it.

A full Kali VM eats disk, battery and patience. This is the same toolset in a
container you throw away at the end of every session — you drive all of it
through `./deck`.

New to TryHackMe or Hack The Box? Skip to [Your first room](#your-first-room).
It walks from a fresh clone to a browser pointed at a lab machine.

## Requirements

Docker Desktop running, and roughly 12 GB of free disk.

**Tested only on Apple Silicon (ARM64) macOS with Docker Desktop.** The image
builds for arm64 (GEF and the Go tools are chosen for it), and the networking
model throughout — the Linux VM, `host.docker.internal`, LAN reachability, the
Burp and reverse-shell notes — assumes Docker Desktop's VM. It may work on Intel
macOS or a Linux Docker host with adjustments, but neither is tested or
supported.

## Getting started

```bash
git clone https://github.com/NotebookNomad/icepick-offsec.git
cd icepick-offsec
./deck build        # ~10 GB, 20-30 min the first time. Go make coffee.
./deck wordlists    # once - SecLists and friends onto a shared volume (~2 GB)
./deck shell        # you're in
```

The build is the only slow part and you do it once; after that `./deck shell`
takes a couple of seconds.

Everything you type in that shell runs inside the container, as root, on Kali.
Nothing you install there touches your Mac, and nothing survives you exiting —
**except** whatever you put in `~/workspace`. That's the repo's `workspace/`
folder seen from inside, so notes, loot and scope files go there.

## Your first room

Say you're on a TryHackMe room with a web app. Start the machine on the room
page, note the IP it gives you, and download your OpenVPN config from
[the access page](https://tryhackme.com/access).

**1. Connect, with a proxy for your browser.**

```bash
./deck vpn ~/Downloads/yourname.ovpn --socks
```

That copies the config into `workspace/`, brings up the tunnel, starts a SOCKS5
proxy on `127.0.0.1:1080`, and drops you into a shell that's on the VPN. It
prints your `tun0` address — your IP on the lab network, and the one you'll put
in reverse shells later.

Check you can reach the box:

```bash
ping -c 3 10.10.115.42
nmap -sC -sV 10.10.115.42
```

**2. Point a browser at it.**

The VPN lives inside the container, so your Mac has no route to `10.10.x.x` by
itself. In Firefox: Settings → Network Settings → **Manual proxy
configuration**, SOCKS Host `127.0.0.1`, Port `1080`, **SOCKS v5**, and tick
**Proxy DNS when using SOCKS v5**.

`http://10.10.115.42` now loads. Every tab in that window goes through the
container — harmless, it has normal internet too — but a separate Firefox
profile keeps it out of your everyday browsing.

**3. When the room uses hostnames.**

Plenty of rooms hand you a name rather than an IP, or hide a second site behind
a vhost (`blog.thm`, `admin.blog.thm`). Because of that DNS checkbox, names are
resolved *inside* the container, which is where they have to be defined — your
Mac's `/etc/hosts` stays untouched:

```bash
hosts add 10.10.115.42 blog.thm admin.blog.thm
```

Then browse `http://blog.thm`. Type the `http://`, or Firefox treats a bare
`.thm` name as a search. Entries are saved in `workspace/hosts.thm` and
re-applied every time you open a shell, since the container itself is thrown
away each session. A room gives you a different IP each time you start it, so
re-running `hosts add` with the same names replaces the old line rather than
leaving a stale one to win the lookup.

To hunt for vhosts you haven't been given:

```bash
ffuf -u http://10.10.115.42 -H 'Host: FUZZ.blog.thm' \
     -w $WORDLISTS/SecLists/Discovery/DNS/subdomains-top1million-5000.txt
```

Every miss comes back the same size, so add `-fs <that size>` on the second run
to leave only the hits.

**4. Keep your notes on the host.**

```bash
cd ~/workspace       # the repo's workspace/ folder, open in your Mac editor too
```

Exit the shell when you're done. That tears down the container, the tunnel and
the proxy together.

## When something doesn't work

- **`tun0 not up yet`** — most HTB/THM configs just work, but one that asks for
  a username and password needs `openvpn --config ~/workspace/lab.ovpn` run by
  hand. `cat /tmp/openvpn.log` tells you which.
- **Can't reach the box** — check it's still started on the room page; lab
  machines expire on their own after an hour or two. Also don't run
  `lockdown-lan` during a VPN session: it blocks `10.0.0.0/8`, which is exactly
  where the boxes live.
- **Browser can't find `blog.thm`** — either "Proxy DNS when using SOCKS v5"
  isn't ticked, or the name isn't in `hosts`.
- **`nmap` says `Operation not permitted`** — something removed `NET_ADMIN` from
  `docker-compose.yml`. See [below](#do-not-remove-net_admin).
- **"port is already allocated"** — an old session is still up. `./deck status`,
  then `./deck stop`.

## Usage

```
./deck shell              interactive shell
./deck listen [ports...]  shell with listener ports published to the LAN
./deck vpn <file.ovpn>    connect an HTB/THM VPN, then drop into a shell
      [--socks [port]]    ...plus a SOCKS5 proxy for a browser on the host
./deck run <cmd...>       one-shot command, no shell
./deck status             what's running
./deck stop               stop everything
./deck clean --volumes    also drop wordlists + tool config (prompts first)
```

In the shell: `whereami` shows user/caps/egress, `lockdown-lan` blocks your LAN,
`inscope` reads `workspace/scope.txt`, `burp on` proxies through Burp, `hosts`
manages lab vhosts.

## The lab proxy, in detail

`tun0` lives in the container's network namespace, so nothing on the host can
route to the lab. `--socks` publishes a SOCKS5 proxy on the host's loopback and
sends the browser back through the container. Pass a port if 1080 is taken
(`--socks 9050`).

Burp can use it too — Network > Connections > SOCKS proxy, plus **Do DNS lookups
over SOCKS proxy** — which puts your browsing and your CLI recon in one sitemap.

The `hosts` command is the vhost half of it:

```bash
hosts add 10.10.115.42 blog.thm admin.blog.thm   # write + apply now
hosts                                            # what's set
hosts load                                       # re-apply after editing the file
```

Two cautions. The proxy takes no credentials, so for as long as that shell lives
it's an open door onto the lab network for anything else on the compose network
— it is published to `127.0.0.1` only, not your LAN, but don't leave sessions
lying around. And `lockdown-lan` and a lab VPN don't mix, for the reason above.

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

`kali-linux-headless` (1342 packages), plus 23 tools it leaves out, plus 8 built
from source.

The 23 are the measured gap, not a curation — headless ships no ProjectDiscovery
tools (`nuclei`, `httpx`, `subfinder`, `naabu`, `dnsx`) and no debugger (`gdb`,
`strace`, `checksec`, `pwntools`). `microsocks` is the one addition that isn't a
gap: it backs `deck vpn --socks`. The 8 (`katana`, `dalfox`, `gau`,
`waybackurls`, `anew`, `unfurl`, `qsreplace`, `gf`) aren't in Kali's repo at all.

`gf` has 37 patterns baked in — tomnomnom's examples for grepping responses,
plus `1ndianl33t/Gf-Patterns` for vulnerable URL params (`ssrf`, `xss`, `sqli`,
`lfi`, `idor`...). `gf -list` shows them.

Wordlists aren't in the image — SecLists alone is 1.8 GB. `./deck wordlists`
puts SecLists, assetnote, PayloadsAllTheThings and `rockyou.txt` on a named
volume, reachable as `$WORDLISTS` inside the shell (`sl` cds into SecLists).

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

# ...or with a SOCKS5 proxy, to browse the lab from the host's browser
./deck vpn ~/Downloads/lab.ovpn --socks
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
deck                    build / shell / vpn / run / wordlists / clean
config/                 zshrc, tmux.conf
scripts/                fetch-wordlists, lockdown-lan, vpn-connect
workspace/              shared with the host
```

---

For authorized testing only — programs you're enrolled in, CTFs you're playing,
systems you own. The isolation here protects *you* from the tools and the
targets; it confers no authorization to point them at anyone.
