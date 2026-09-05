# vpn/

Drop your `.ovpn` files here. `./deck vpn` picks one up automatically:

| what's in here | what `./deck vpn` does |
| --- | --- |
| nothing | tells you to put a config here |
| one `.ovpn` | uses it, no argument needed |
| several | lists them and asks which, with an option to cancel |

Name one directly to skip the prompt — `./deck vpn lab.ovpn` — which is also how
you pick a config from a script, where there is nobody to answer a menu.

A path outside the repo still works and is copied in here:

```sh
./deck vpn ~/Downloads/lab.ovpn
```

The directory is mounted read-only at `/root/vpn` in the container, so configs
stay out of `workspace/`, which is where loot and notes accumulate.

**Everything here except this file and `.gitkeep` is gitignored**, so configs and
any credentials beside them cannot be committed by accident. They are still
plaintext on disk — treat the directory as you would an SSH private key.

With a config present, `tests/integration/vpn.bats` stops skipping and exercises
the parts no synthetic fixture can reach: the tunnel coming up, surviving
`lockdown-wan`'s policy flip, and the SOCKS proxy reaching through it.
