# Your first room

This goes from a fresh clone to a browser pointed at a live lab machine. It
assumes a TryHackMe room with a web app, but Hack The Box works the same way.
Unfamiliar word? See the [glossary](glossary.md).

Start the machine on the room page, note the IP it gives you, and download your
OpenVPN config from [the access page](https://tryhackme.com/access).

## 1. Connect, with a proxy for your browser

Put the `.ovpn` in the repo's `vpn/` folder, then:

```bash
./deck vpn --socks
```

One config in `vpn/` and it just uses it. Several, and it lists them and asks
which — `0` backs out. You can name one instead (`./deck vpn lab.ovpn`), which
is also how you pick from a script, and a path from anywhere still works and is
copied in:

```bash
./deck vpn ~/Downloads/yourname.ovpn --socks
```

That brings up the VPN tunnel, starts a SOCKS5 proxy on `127.0.0.1:1080` — a
relay your browser can use to reach the lab network — and drops you into a shell
that's on the VPN. It prints your `tun0` address, which is your own IP address
on the lab network and the one you'll put in reverse shells later.

Check you can reach the box:

```bash
ping -c 3 10.10.115.42
nmap -sC -sV 10.10.115.42
```

## 2. Point a browser at it

The VPN lives inside the container, so the host has no route to `10.10.x.x` by
itself. In Firefox: Settings → Network Settings → **Manual proxy
configuration**, SOCKS Host `127.0.0.1`, Port `1080`, **SOCKS v5**, and tick
**Proxy DNS when using SOCKS v5**.

`http://10.10.115.42` now loads. Every tab in that window goes through the
container — harmless, it has normal internet too — but a separate Firefox
profile keeps it out of your everyday browsing.

## 3. When the room uses hostnames

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

## 4. Keep your notes on the host

```bash
cd ~/workspace       # the repo's workspace/ folder, open in your host editor too
```

Exit the shell when you're done. That tears down the container, the tunnel and
the proxy together.

## When something doesn't work

Setup-stage problems:

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

Once you're working:

- **`tun0 not up yet`** — most HTB/THM configs just work, but one that asks for
  a username and password needs `openvpn --config ~/vpn/lab.ovpn` run by
  hand. `cat /tmp/openvpn.log` tells you which.
- **Can't reach the box** — check it's still started on the room page; lab
  machines expire on their own after an hour or two. Also don't run
  `lockdown-lan` during a VPN session: it blocks `10.0.0.0/8`, which is exactly
  where the boxes live.
- **Browser can't find `blog.thm`** — either "Proxy DNS when using SOCKS v5"
  isn't ticked, or the name isn't in `hosts`.
- **`nmap` says `Operation not permitted`** — something removed `NET_ADMIN` from
  `docker-compose.yml`. See [internals](internals.md#do-not-remove-net_admin).
- **"port is already allocated"** — an old session is still up. `./deck status`,
  then `./deck stop`.

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
