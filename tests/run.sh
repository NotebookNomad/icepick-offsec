#!/usr/bin/env bash
# Run the bats suites.  Usage: tests/run.sh [static|unit|integration|all]...
# With no argument: static + unit (the fast, dependency-light layers).
set -euo pipefail
cd "$(dirname "$0")"

BATS=./bats/bin/bats
if [ ! -x "$BATS" ]; then
  echo "bats submodule missing. Run:  git submodule update --init --recursive" >&2
  exit 1
fi

want=("$@")
[ ${#want[@]} -eq 0 ] && want=(static unit)

dirs=()
for s in "${want[@]}"; do
  case "$s" in
    all) for d in static unit integration; do [ -d "$d" ] && dirs+=("$d"); done ;;
    static|unit|integration)
      if [ -d "$s" ]; then dirs+=("$s"); else echo "no such suite dir: $s (skipping)" >&2; fi ;;
    *) echo "unknown suite: $s  (static|unit|integration|all)" >&2; exit 2 ;;
  esac
done

[ ${#dirs[@]} -gt 0 ] || { echo "nothing to run" >&2; exit 2; }

echo ">> bats $("$BATS" --version | awk '{print $2}')  suites: ${dirs[*]}"
exec "$BATS" --print-output-on-failure --recursive "${dirs[@]}"
