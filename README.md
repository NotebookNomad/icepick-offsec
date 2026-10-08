# icepick-offsec

**A disposable Kali toolbox for authorized bug bounty and CTF work, driven by one
command — with the HTB/THM VPN-and-browser problem already solved.**

A few hundred Kali tools run inside a throwaway Docker container you drive with
`./deck`. One command connects a lab VPN *and* hands your everyday browser a
proxy onto the target network — the routing, DNS and vhost dance that TryHackMe
and Hack The Box otherwise leave you to wire up by hand:

```bash
./deck vpn --socks     # tunnel up, SOCKS proxy on 127.0.0.1:1080, shell on the VPN
```

Every session is a clean container that's deleted when you exit, so the tools
never touch the machine you live on — no VM eating disk and battery, no Kali
packages smeared across your daily driver. The name nods to cyberpunk ICE
(Intrusion Countermeasures Electronics): an icepick breaks it.

**Why this over `docker run kalilinux/kali-rolling`?** That gives you a bare
rolling image and a blank prompt. This adds the tools headless Kali leaves out,
the one-command VPN / proxy / lockdown flow above, fail-closed egress firewalls
so a mistyped target can't leave the tunnel, and a test suite that keeps it all
honest — see [Going deeper](#going-deeper).

> **New to this?** Read the four points below, run the
> [Getting started](#getting-started) commands, then follow
> **[Your first room](docs/walkthrough.md)** — fresh clone to a browser pointed
> at a live lab machine. Unfamiliar word? There's a [glossary](docs/glossary.md).

## How it works

- **`./deck` is the only command you run on your own machine.** It's a small
  wrapper around Docker. `./deck shell` drops you inside Kali, and everything
  you type after that runs in the container, not on your computer.
- **Every session is disposable.** You get a clean container each time, and it's
  deleted the moment you exit. A tool that scribbles all over the filesystem is
  scribbling on something you were about to throw away.
- **`workspace/` survives.** That folder in this repo is shared with the
  container, where it shows up as `~/workspace`. Notes, loot, scope files and
  CTF binaries go there. Everything else is gone when you exit.
- **VPN configs go in `vpn/`.** Drop your `.ovpn` there and `./deck vpn` finds
  it. It's mounted read-only and kept apart from `workspace/` because a lab
  config is a credential. Both folders are gitignored.

## Requirements

- **Docker**, running. [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  on macOS, or Docker Engine on Linux. Launch it before you run anything below.
- **Roughly 12 GB of free disk.**

macOS or Linux, Intel or Apple Silicon — the image builds for whatever you're
on, and `./deck` sorts out the differences itself. (Windows via WSL2 ought to
work, since the container is Linux either way, but it's untested.) You can also
run it on a server and drive it from a laptop or tablet — see
[Running it on a remote host](docs/networking.md#running-it-on-a-remote-host).

Two host details occasionally matter — VPN support needs `/dev/net/tun` (any
Docker Desktop or ordinary Linux box has it; container-based VPSes like OpenVZ
don't), and CPU architecture decides whether CTF binary-exploitation tools can
run the x86-64 binaries most pwn challenges ship. Both are covered in
[internals](docs/internals.md).

## Getting started

```bash
git clone https://github.com/NotebookNomad/icepick-offsec.git
cd icepick-offsec
./deck build        # ~10 GB, 20-30 min the first time. Go make coffee.
./deck wordlists    # once - SecLists and friends onto a shared volume (~2 GB)
./deck shell        # you're in
```

Those first two commands are one-time setup. After that, `./deck shell` takes a
couple of seconds and is how you start every session.

You'll know it worked when your prompt changes to `[deck]` and a short banner
lists a few commands. Try this first:

```bash
whereami            # who you are, what the container can do, is the internet up
exit                # back to your own machine; the container is deleted
```

Being `root` in there is normal and safe — it's root *of the container*, not of
your computer. ([Why it runs as root](docs/internals.md#why-it-runs-as-root).)

**Next:** walk through a real lab in **[Your first room](docs/walkthrough.md)**.

## Commands

```
./deck build              build the image (once, and after you edit it)
./deck wordlists          download the wordlists (once)
./deck shell              interactive shell
./deck listen [ports...]  shell with listener ports published on the host
./deck vpn [file.ovpn]    connect an HTB/THM VPN, then drop into a shell
                          (no argument: use or choose from vpn/)
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

## Going deeper

- **[Your first room](docs/walkthrough.md)** — the full hands-on walkthrough,
  troubleshooting, and copy-paste recipes.
- **[Networking](docs/networking.md)** — the SOCKS proxy and vhosts, keeping
  traffic inside the VPN (`lockdown-wan`), reverse shells and callbacks, Burp
  Suite, and running on a remote host.
- **[Internals & design](docs/internals.md)** — what's in the image, why it runs
  as root, the `NET_ADMIN` requirement, the contract with the autonomous
  overlay, and the toolkit's limits.
- **[Glossary](docs/glossary.md)** — the jargon, plainly.

## Two things not to "clean up"

If you're tempted to harden the compose file, read these first — both are
load-bearing and the full reasoning is in [internals](docs/internals.md).

- **Don't remove `NET_ADMIN`** from `docker-compose.yml`. It looks like
  hardening, but nmap won't even `exec` without it (Kali's nmap carries
  `cap_net_admin` as a *file* capability), and `lockdown-lan` and `openvpn` both
  need it. [Details.](docs/internals.md#do-not-remove-net_admin)
- **This image is another image's base.** A second repo builds `FROM` it and
  depends on exact tool names and one shared Python interpreter, so a rename that
  looks like tidying can break the overlay at *its* runtime.
  [Details.](docs/internals.md#this-image-is-another-images-base)

## Layout

```
Dockerfile              two-stage: Go tools, then Kali runtime
docker-compose.yml      the container and its isolation settings
deck                    build / shell / vpn / run / wordlists / clean
config/                 zshrc, tmux.conf
scripts/                deck's helpers: callback-addr, fetch-wordlists, lockdown-*, vpn-connect
docs/                   walkthrough, networking, internals, glossary
tests/                  bats suites - see tests/README.md
vpn/                    drop .ovpn files here; mounted read-only, gitignored
workspace/              shared with the host
```

---

For authorized testing only — programs you're enrolled in, CTFs you're playing,
systems you own. The isolation here protects *you* from the tools and the
targets; it confers no authorization to point them at anyone.
