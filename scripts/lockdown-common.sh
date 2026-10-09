#!/usr/bin/env bash
# Shared fail-closed preflight for lockdown-lan and lockdown-wan. Sourced, not
# run: `. lockdown-common.sh` (both live in /usr/local/bin, which is on PATH in
# the container, so the bare name resolves). Defines two guards; each exits the
# calling script on failure rather than returning, because there is nothing
# sensible to do past a failed precondition here.

# Both scripts need NET_ADMIN to write iptables rules. Decode CapEff from /proc,
# not `capsh --print`: its "Current IAB" line prints !cap_net_admin when absent,
# and a plain grep would match that negated entry.
require_net_admin() {
  local eff
  eff=$(capsh --decode="$(awk '/^CapEff/{print $2}' /proc/self/status)" 2>/dev/null)
  if ! printf '%s' "$eff" | grep -q net_admin; then
    echo "error: needs NET_ADMIN - check cap_add in docker-compose.yml." >&2
    exit 1
  fi
}

# Refuse to claim a firewall is up when no rule could be written - the one
# failure mode that matters. $1 names what we would otherwise be claiming
# falsely ("the LAN is blocked", "egress is blocked").
require_iptables() {
  if ! iptables -L >/dev/null 2>&1; then
    echo "error: iptables unavailable - refusing to claim $1." >&2
    exit 1
  fi
}
