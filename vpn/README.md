# vpn/

Drop your `.ovpn` files here. With one config present, `./deck vpn` just uses
it; with several, it asks which. The folder is mounted read-only in the
container and kept apart from `workspace/` because a lab config is a credential.

See **[Your first room](../docs/walkthrough.md)** for the walkthrough and
**[Networking](../docs/networking.md)** for the proxy and lockdown options.

> **Everything here except this file and `.gitkeep` is gitignored**, so configs
> and any credentials beside them can't be committed by accident. They're still
> plaintext on disk — treat this directory as you would an SSH private key.
