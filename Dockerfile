# syntax=docker/dockerfile:1.7
#
# Kali toolkit for bug bounty / CTF work. ~10 GB, one build, no options.
# Wordlists are not baked in - `fetch-wordlists` puts them on a volume.

# ---------------------------------------------------------------------------
# Stage 1 - the 8 Go tools Kali does not package
# ---------------------------------------------------------------------------
FROM golang:1-bookworm AS gotools

ENV GOBIN=/out \
    GOFLAGS=-trimpath \
    CGO_ENABLED=0

# @latest, not pinned: for security tooling fresh beats reproducible.
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    for pkg in \
      github.com/projectdiscovery/katana/cmd/katana \
      github.com/hahwul/dalfox/v2 \
      github.com/lc/gau/v2/cmd/gau \
      github.com/tomnomnom/waybackurls \
      github.com/tomnomnom/anew \
      github.com/tomnomnom/unfurl \
      github.com/tomnomnom/qsreplace \
      github.com/tomnomnom/gf \
    ; do echo ">> $pkg" && go install "$pkg@latest" || exit 1 ; done

# ---------------------------------------------------------------------------
# Stage 2 - runtime
# ---------------------------------------------------------------------------
FROM kalilinux/kali-rolling

# ARG, not ENV: apt needs it during the build, but persisting it would make a
# hand-run `apt-get install` inside the container skip its prompts too.
ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# --- base system ------------------------------------------------------------
# pipx is here for ad-hoc installs in a session: PEP 668 blocks plain `pip`.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git openssh-client \
      vim nano less tmux zsh bash-completion \
      jq ripgrep fd-find bat unzip zip p7zip-full xz-utils \
      build-essential pkg-config \
      python3 python3-pip python3-venv pipx \
      ruby ruby-dev \
      locales tzdata procps psmisc file \
 && rm -rf /var/lib/apt/lists/*

# --- toolset ----------------------------------------------------------------
# Only what kali-linux-headless does NOT pull in, measured by diffing its
# dependencies: it ships no ProjectDiscovery tools and no debugger. The last
# line (autorecon/enum4linux-ng/feroxbuster + openvpn) is shared with the
# autonomous overlay that builds FROM this image; openvpn also backs `deck vpn`.
RUN apt-get update \
 && apt-get install -y --no-install-recommends kali-linux-headless \
 && apt-get install -y --no-install-recommends \
        netcat-openbsd iputils-ping dnsutils iptables microsocks openvpn \
        nuclei httpx-toolkit subfinder naabu dnsx assetfinder arjun \
        autorecon enum4linux-ng feroxbuster \
        gdb gdbserver ltrace strace patchelf checksec python3-pwntools \
        foremost steghide uro name-that-hash \
 && rm -rf /var/lib/apt/lists/*

# Kali ships projectdiscovery's httpx as httpx-toolkit because python3-httpx
# owns /usr/bin/httpx. Assert with `test -x` first: `ln -s` exits 0 on a
# dangling link, which would hide a renamed package until runtime.
RUN test -x /usr/bin/httpx-toolkit \
 && ln -s /usr/bin/httpx-toolkit /usr/local/bin/httpx

# The only two tools not packaged by Kali or Debian.
RUN gem install --no-document one_gadget seccomp-tools

# GEF loads from gdb's system-wide init. mkdir first: /etc/gdb exists only if
# the gdb package created it.
RUN curl -fsSL -o /opt/gef.py https://raw.githubusercontent.com/hugsy/gef/main/gef.py \
 && mkdir -p /etc/gdb \
 && printf 'source /opt/gef.py\n' >> /etc/gdb/gdbinit

# gf reads only $HOME/.gf and has no path override, so the patterns are baked
# in - on a volume `run --rm` would lose them. Two repos, disjoint names.
RUN git clone --depth 1 --quiet https://github.com/1ndianl33t/Gf-Patterns /tmp/gfp \
 && git clone --depth 1 --quiet https://github.com/tomnomnom/gf /tmp/gf \
 && mkdir -p /root/.gf \
 && cp /tmp/gfp/*.json /root/.gf/ \
 && cp /tmp/gf/examples/*.json /root/.gf/ \
 && rm -rf /tmp/gf /tmp/gfp

# rustscan - not packaged by Kali/Debian and no upstream multiarch binary, so
# build from source. cargo runs on arm64 and amd64 alike; copy the one binary
# out and drop the ~1 GB toolchain in the SAME layer so it never ships.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable --profile minimal \
 && /root/.cargo/bin/cargo install rustscan \
 && cp /root/.cargo/bin/rustscan /usr/local/bin/rustscan \
 && rm -rf /root/.cargo /root/.rustup

# Heavy Python exploit libs Kali does not package (angr, ROPgadget). Kept in a
# dedicated venv, NOT system python: this image is PEP-668 externally-managed and
# angr drags in pinned deps that would otherwise fight apt's python3-* packages.
# --system-site-packages lets the venv still see the apt python3-pwntools, so a
# single interpreter (/opt/pyenv/bin/python3) has the whole pwn+angr+ROPgadget
# trio - matching how the autonomous image exposed them. CLIs are linked onto PATH.
RUN python3 -m venv --system-site-packages /opt/pyenv \
 && /opt/pyenv/bin/pip install --no-cache-dir --upgrade pip wheel setuptools \
 && /opt/pyenv/bin/pip install --no-cache-dir angr ropgadget \
 && ln -s /opt/pyenv/bin/ROPgadget /usr/local/bin/ROPgadget \
 && printf '#!/bin/sh\nexec /opt/pyenv/bin/python3 "$@"\n' > /usr/local/bin/angr-python \
 && chmod +x /usr/local/bin/angr-python

# jwt_tool, exposed as `jwt-analyzer` (the name HexStrike's JWT probe calls). Its
# deps live in the /opt/pyenv venv above to keep system python clean.
RUN git clone --depth 1 https://github.com/ticarpi/jwt_tool.git /opt/jwt_tool \
 && /opt/pyenv/bin/pip install --no-cache-dir pycryptodomex termcolor cryptography requests \
 && printf '#!/bin/sh\nexec /opt/pyenv/bin/python3 /opt/jwt_tool/jwt_tool.py "$@"\n' \
      > /usr/local/bin/jwt-analyzer \
 && chmod +x /usr/local/bin/jwt-analyzer

# --- Go tools from stage 1 --------------------------------------------------
COPY --from=gotools /out/ /usr/local/bin/

# --- config -----------------------------------------------------------------
# Last, so editing one of these does not rebuild anything above it.
COPY config/zshrc     /root/.zshrc
COPY config/tmux.conf /root/.tmux.conf
# The whole directory, not four named files: adding a script should be one new
# file, not an edit here as well. tests/static/*.bats glob scripts/* for the
# same reason, and tests/integration/image.bats checks what landed.
COPY scripts/ /usr/local/bin/

WORKDIR /root/workspace

ENV PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

CMD ["/usr/bin/zsh", "-l"]
