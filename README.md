# icepick-offsec

A ready-made Kali Linux toolbox for authorized bug bounty work and CTF labs like
TryHackMe and Hack The Box. It runs in a Docker container, so a few hundred
security tools end up in a sandbox you throw away rather than installed on your
computer. You drive all of it with one script: `./deck`.

Installing Kali properly means a VM that eats disk, battery and patience — or
mixing hundreds of security tools into the machine you actually live in. This is
the same toolset, disposable. The name nods to cyberpunk ICE (Intrusion
Countermeasures Electronics): an icepick breaks it.

**Never done this before?** Read the three bullets just below, run the commands
in [Getting started](#getting-started), then follow
[Your first room](#your-first-room) — it goes from a fresh clone to a browser
pointed at a live lab machine. Unfamiliar word? There's a
[glossary](#glossary) at the bottom.

## How it works

- **`./deck` is the only command you run on your own machine.** It's a small
  wrapper around Docker. `./deck shell` drops you inside Kali, and everything
  you type after that runs in the container, not on your computer.
- **Every session is disposable.** You get a clean container each time, and it's
  deleted the moment you exit. That's the point — a tool that scribbles all over
  the filesystem is scribbling on something you were about to throw away.
- **`workspace/` is the one exception.** That folder in this repo is shared with
  the container, where it shows up as `~/workspace`. Notes, loot, scope files
  and CTF binaries go there and survive. Everything else is gone when you exit.

## Requirements

- **Docker**, running. [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  on macOS, or Docker Engine on Linux. Launch it before you run anything below.
- **Roughly 12 GB of free disk.**

macOS or Linux, Intel or Apple Silicon — the image builds for whatever you're
on, and `./deck` sorts out the differences itself. (Windows via WSL2 ought to
work, since the container is Linux either way, but it's untested.) You can also
run it on a server and drive it from a laptop or tablet — see
[Running it on a remote host](#running-it-on-a-remote-host).

<details>
<summary><b>Two host details that occasionally matter</b> — VPN support and CPU
architecture. Skip unless something below bites you.</summary>

- **`/dev/net/tun` is what `./deck vpn` needs.** Docker Desktop always has it,
  as does any ordinary Linux machine. Only container-based VPSes (OpenVZ, LXC)
  can't provide it, and there the container won't start at all — check with
  `ls -l /dev/net/tun` before paying for one. Full-virtualisation VPSes (KVM,
  Xen) are fine.
- **Architecture decides the CTF binary-exploitation half.** `gdb`/GEF,
  `pwntools`, `one_gadget` and `checksec` all run native, so an Intel/AMD host
  debugs the x86-64 binaries that nearly every pwn challenge ships. On Apple
  Silicon those binaries are the wrong architecture and would need qemu-user,
  which isn't in the image. Web and recon tooling doesn't care either way.

</details>

## Getting started

```bash
git clone https://github.com/NotebookNomad/icepick-offsec.git
cd icepick-offsec
./deck build        # ~10 GB, 20-30 min the first time. Go make coffee.
./deck wordlists    # once - SecLists and friends onto a shared volume (~2 GB)
./deck shell        # you're in
```

Those first two commands are one-time setup. After that, `./deck shell` takes a
couple of seconds and is how you start every session from then on.

You'll know it worked when your prompt changes to `[deck]` and a short banner
lists a few commands. Try this first:

```bash
whereami            # who you are, what the container can do, is the internet up
exit                # back to your own machine; the container is deleted
```

Being `root` in there is normal and safe — it's root *of the container*, not of
your computer. [Why it runs as root](#why-it-runs-as-root) has the details if
you're curious.

## Your first room

Say you're on a TryHackMe room with a web app. Start the machine on the room
page, note the IP it gives you, and download your OpenVPN config from
[the access page](https://tryhackme.com/access).

**1. Connect, with a proxy for your browser.**

```bash
./deck vpn ~/Downloads/yourname.ovpn --socks
```

That copies the config into `workspace/`, brings up the VPN tunnel, starts a
SOCKS5 proxy on `127.0.0.1:1080` — a relay your browser can use to reach the lab
network — and drops you into a shell that's on the VPN. It prints your `tun0`
address, which is your own IP address on the lab network and the one you'll put
in reverse shells later.

Check you can reach the box:

```bash
ping -c 3 10.10.115.42
nmap -sC -sV 10.10.115.42
```

**2. Point a browser at it.**

The VPN lives inside the container, so the host has no route to `10.10.x.x` by
itself. In Firefox: Settings → Network Settings → **Manual proxy
configuration**, SOCKS Host `127.0.0.1`, Port `1080`, **SOCKS v5**, and tick
**Proxy DNS when using SOCKS v5**.

`http://10.10.115.42` now loads. Every tab in that window goes through the
container — harmless, it has normal internet too — but a separate Firefox
profile keeps it out of your everyday browsing.

**3. When the room uses hostnames.**

Plenty of rooms hand you a name rather than an IP, or hide a second site behind
a vhost — a separate site on the same IP address, picked out by the hostname you
ask for (`blog.thm`, `admin.blog.thm`). Because of that DNS checkbox, names are
resolved *inside* the container, which is where they have to be defined — the
host's `/etc/hosts` stays untouched:

```bash
hosts add 10.10.115.42 blog.thm admin.blog.thm
```

Then browse `http://blog.thm`. Type the `http://`, or Firefox treats a bare
`.thm` name as a search. Entries are saved in `workspace/hosts.thm` and
re-applied every time you open a shell, since the container itself is thrown
away each session. A room gives you a different IP each time you start it, so
the most recent entry for a name wins — re-run `hosts add` after a restart and
the new address takes over, while any other vhost you set up stays put. The file
itself is only ever appended to, so notes and comments in it survive, and
`hosts load` applies the same last-wins rule to edits you make by hand.

To hunt for vhosts you haven't been given:

```bash
ffuf -u http://10.10.115.42 -H 'Host: FUZZ.blog.thm' \
     -w $WORDLISTS/SecLists/Discovery/DNS/subdomains-top1million-5000.txt
```

Every miss comes back the same size, so note that size and re-run with
`-fs <that size>` to filter them out, leaving only the real hits.

**4. Keep your notes on the host.**

```bash
cd ~/workspace       # the repo's workspace/ folder, open in your host editor too
```

Exit the shell when you're done. That tears down the container, the tunnel and
the proxy together.

## When something doesn't work

Start here if you're new — these are the setup-stage ones:

- **`Cannot connect to the Docker daemon`** — Docker isn't running. Start Docker
  Desktop (or `sudo systemctl start docker` on Linux) and try again.
- **`permission denied: ./deck`** — the script lost its executable bit:
  `chmod +x deck`.
- **`no space left on device` during the build** — the image needs ~10 GB and
  the wordlists another ~2 GB. `docker builder prune` reclaims build cache and
  `docker image prune` drops leftover layers, both safe here. Don't reach for
  `docker system prune -a`: because every session is a `--rm` container, no
  container is holding this image, so `-a` counts it as unused and deletes it.
- **The build failed somewhere in the middle** — usually a network blip while
  fetching packages. Just run `./deck build` again; finished steps are cached,
  so it picks up near where it stopped.

And these come up once you're actually working:

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
./deck build              build the image (once, and after you edit it)
./deck wordlists          download the wordlists (once)
./deck shell              interactive shell
./deck listen [ports...]  shell with listener ports published on the host
./deck vpn <file.ovpn>    connect an HTB/THM VPN, then drop into a shell
      [--socks [port]]    ...plus a SOCKS5 proxy for a browser on the host
      [--lockdown]        ...and block every egress path except the tunnel
./deck run <cmd...>       one-shot command, no shell
./deck status             what's running
./deck stop               stop everything
./deck clean --volumes    also drop wordlists + tool config (prompts first)
```

Commands that exist only inside the container's shell:

```
whereami        who you are, what the container may do, whether the internet works
hosts           add and apply lab hostnames (blog.thm and friends)
burp on|off     route the CLI tools through Burp running on your computer
lockdown-lan    block the container from reaching your home network
lockdown-wan    the inverse: block everything except the VPN tunnel
inscope         print workspace/scope.txt, your list of in-scope targets
fetch-wordlists download the wordlists (same as ./deck wordlists)
sl              jump to the SecLists wordlist folder
```

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
it's an open door onto the lab network. It's published to the host's `127.0.0.1`
only, so nothing off the host can reach it — but anything else on the compose
network can, so don't leave sessions lying around. And `lockdown-lan` and a lab VPN don't mix, for the reason above.

## Keeping traffic inside the VPN

`lockdown-lan` blocks your private network and keeps the internet. During a lab
session you usually want the opposite — nothing but the tunnel — so that a
mistyped target or a tool that resolves outward can't touch anything beyond the
box you're working on. That's `lockdown-wan`:

```bash
./deck vpn lab.ovpn --lockdown        # applied before you get a shell
```

It's applied by `vpn-connect` after the tunnel is up and **before** the shell
starts, because a tool run in the gap between a live tunnel and an applied
firewall is the thing this exists to prevent. It is fail-closed: if the rules
can't be installed you get an error instead of a shell that looks protected and
isn't. You can also run `lockdown-wan` by hand inside any VPN shell.

What stays reachable: loopback, established flows, the Docker bridge subnet (so
the `--socks` proxy can still answer), `tun0`, and the VPN server itself —
resolved from the `.ovpn` before the policy flips, so the tunnel can re-handshake
if it drops. Everything else is dropped, on IPv4 **and** IPv6, and the bridge
gateway — the Docker host itself — is dropped explicitly rather than being swept
up by the subnet allow.

The rules match on the interface a packet leaves by, not its address. That's what
makes this work where `lockdown-lan` can't: HTB and THM labs live in
`10.0.0.0/8`, exactly the range `lockdown-lan` blocks. Don't run both.

**It also empties `/etc/resolv.conf`, and it has to.** Docker's resolver at
`127.0.0.11` is reached over loopback but forwards upstream from outside the
container's network namespace, so DNS queries never traverse the OUTPUT chain and
leak past any iptables rule you write. Emptying the resolver is the only fix
available from inside. Lab names keep working, because `/etc/hosts` is consulted
first and `hosts add` already puts them there — but public names stop resolving,
which is the point. `KEEP_DNS=1` skips it and warns.

Like `lockdown-lan`, the rules are per container and die with the session. And
the same caveat applies to both: the container has `NET_ADMIN`, so anything
running in it can flush these rules. This stops accidents, not hostile code.

## Reverse shells and callbacks

A normal container publishes no ports, so a listener started inside it binds to
the private bridge IP and nothing off-host can reach it. Where the callback
needs to land depends on where the target is:

- **HTB / THM** — `./deck vpn lab.ovpn` connects and drops you in a shell.
  `openvpn` creates `tun0`, a routable address on the target's own network, so
  `nc -lvnp 4444` works with no publishing. Put your `tun0` IP (`ip addr show tun0`) in the
  payload.
- **A host on your LAN** — `./deck listen` publishes ports (default
  `4444 8000 9001 443`, or pass your own) to the host, and prints the address on
  the default route to aim callbacks at. Those ports stay open to anything that
  can reach that address until you exit.
- **The public internet** — behind a home router, neither helps; you're on the
  far side of NAT, so use a tunnel (ngrok, SSH reverse tunnel) as the
  redirector. On a host that already has a public IP, `./deck listen` *is* the
  redirector, but the ports are then exposed to the internet and your provider's
  firewall is the other half of the job. Check the address it prints, too: it
  reads the host's own interface, so on AWS, GCE and Azure — where the public IP
  is NAT'd upstream and never appears locally — you'll get a private `10.x`
  address. `curl ifconfig.me` gives you the one a target can actually reach.

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

If your listener isn't on the default host and port, set `BURP_HOST` /
`BURP_PORT` — either on the host, where `./deck` passes them in, or inside the
shell before you run `burp on`:

```bash
BURP_HOST=192.168.1.20 BURP_PORT=9090 ./deck shell
```

## Running it on a remote host

Nothing assumes the Docker host is the machine you're typing on. Clone and build
on a VPS, drive it over SSH — which is also how you use this from a tablet or a
Chromebook. Two things change.

**Sessions have to outlive the connection.** `deck` uses `docker compose run
--rm`, so a dropped SSH session takes the container and whatever was running in
it. Start tmux on the remote host, not just inside the container:

```bash
ssh vps
tmux new -As deck     # same command reattaches after a disconnect
./deck shell
```

On a mobile or flaky link, `mosh` instead of `ssh` is worth the install — it
survives address changes and a sleeping client, which plain SSH does not.

**Loopback is now the remote host's loopback.** `deck vpn --socks` publishes the
proxy to `127.0.0.1` on the Docker host, and that stays right: on a box with a
public IP, binding it wider is an unauthenticated route into the lab network,
open to the internet. Forward the port rather than rebinding it —

```bash
ssh -L 1080:127.0.0.1:1080 vps
```

— and point your browser at `127.0.0.1:1080` locally, exactly as if the
container were under your desk. Note that the SOCKS proxy is the *only* way in:
`tun0` lives in the container's network namespace, so forwarding some other port
off the VPS reaches nothing, because nothing on the VPS is listening on it.

Burp is the one piece that assumes a GUI on the Docker host. On a headless
remote, the simple answer is to skip it and use the SOCKS proxy. Forwarding your
local Burp in with `ssh -R` does work, but it's fiddly: the reverse forward has
to bind an address the container can reach rather than the VPS's loopback, which
means `GatewayPorts clientspecified` in the remote `sshd_config`, and then
`BURP_HOST` set to that address when you start the shell.

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
and the default seccomp profile are on. How much an escape would cost you does
depend on the host, though: under Docker Desktop it lands in Docker's Linux VM,
while on a Linux Docker host it lands on the host kernel itself.

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

## Glossary

Terms this README uses that are worth pinning down if you're new:

- **container** — an isolated Linux environment sharing your machine's kernel.
  Lighter than a VM, and here, thrown away after every session.
- **image** — the built template a container is started from. `./deck build`
  makes it once; every `./deck shell` starts a fresh container from it.
- **volume** — Docker-managed storage that outlives any single container. The
  wordlists and your tool API keys live on volumes, which is why they survive.
- **`tun0`** — the network interface OpenVPN creates. Its IP address is *your*
  address on the lab network, so it's what a target calls back to.
- **SOCKS proxy** — a relay that carries any TCP connection. `--socks` gives you
  one so your ordinary browser can reach lab machines it has no route to.
- **vhost** — several websites served from one IP address, chosen by the
  hostname in the request. Why `blog.thm` and `admin.blog.thm` can be different
  sites at the same address.
- **reverse shell / callback** — instead of you connecting to a target, you make
  the target connect back to a **listener** you're running. See
  [Reverse shells and callbacks](#reverse-shells-and-callbacks).
- **wordlist** — a big text file of candidate names or passwords that tools like
  `ffuf` and `gobuster` try one by one.
- **scope** — the targets a bug bounty program actually permits you to test.
  Going outside it is the line between research and an incident.

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
