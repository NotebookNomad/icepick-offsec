# Glossary

Terms the docs use that are worth pinning down if you're new:

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
  [Reverse shells and callbacks](networking.md#reverse-shells-and-callbacks).
- **wordlist** — a big text file of candidate names or passwords that tools like
  `ffuf` and `gobuster` try one by one.
- **scope** — the targets a bug bounty program actually permits you to test.
  Going outside it is the line between research and an incident.
