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
# dependencies: it ships no ProjectDiscovery tools and no debugger.
RUN apt-get update \
 && apt-get install -y --no-install-recommends kali-linux-headless \
 && apt-get install -y --no-install-recommends \
        netcat-openbsd iputils-ping dnsutils iptables microsocks \
        nuclei httpx-toolkit subfinder naabu dnsx assetfinder arjun \
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

# --- Go tools from stage 1 --------------------------------------------------
COPY --from=gotools /out/ /usr/local/bin/

# --- config -----------------------------------------------------------------
# Last, so editing one of these does not rebuild anything above it.
COPY config/zshrc     /root/.zshrc
COPY config/tmux.conf /root/.tmux.conf
COPY scripts/fetch-wordlists /usr/local/bin/fetch-wordlists
COPY scripts/lockdown-lan    /usr/local/bin/lockdown-lan
COPY scripts/lockdown-wan    /usr/local/bin/lockdown-wan
COPY scripts/vpn-connect     /usr/local/bin/vpn-connect

WORKDIR /root/workspace

ENV PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

CMD ["/usr/bin/zsh", "-l"]
