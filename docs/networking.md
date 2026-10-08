# Networking: proxy, VPN lockdown, callbacks, Burp, remote hosts

Everything about getting traffic in and out of the container. The
[walkthrough](walkthrough.md) covers the common path; this is the detail behind
it.

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
network can, so don't leave sessions lying around. And `lockdown-lan` and a lab
VPN don't mix, for the reason below.

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

If a lab needs one more destination outside the tunnel — a jump host, a
provider-side resolver you decided to keep — `LOCAL_ALLOW_NETS` is permitted
alongside the bridge subnet:

```bash
LOCAL_ALLOW_NETS='192.0.2.10/32' lockdown-wan
```

Like `lockdown-lan`, the rules are per container and die with the session. And
the same caveat applies to both: the container has `NET_ADMIN`, so anything
running in it can flush these rules. This stops accidents, not hostile code.

## Reverse shells and callbacks

A normal container publishes no ports, so a listener started inside it binds to
the private bridge IP and nothing off-host can reach it. Where the callback
needs to land depends on where the target is:

- **HTB / THM** — `./deck vpn lab.ovpn` connects and drops you in a shell.
  `openvpn` creates `tun0`, a routable address on the target's own network, so a
  listener works with no publishing. Put your `tun0` IP (`ip addr show tun0`) in
  the payload.
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
