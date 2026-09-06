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

# The scripts are COPY'd into the image, so a container runs whatever the last
# build captured - and a green integration run against a stale image is exactly
# the false pass this suite exists to prevent.
#
# Check rather than build. Building here looks tidier, but the Dockerfile pulls
# a frontend for its `# syntax=` directive and sits on the moving
# kalilinux/kali-rolling tag, so a build is seconds when warm and tens of
# minutes - or an apt failure - when the network moves or the base shifts. One
# container start and a checksum costs ~2s, needs no network, and refuses to run
# rather than lying.
case " ${dirs[*]} " in
  *" integration "*)
    if docker image inspect icepick-offsec:latest >/dev/null 2>&1; then
      names=$(cd ../scripts && ls | sort | tr '\n' ' ')
      host_sum=$( (cd ../scripts && cat $(ls | sort)) | shasum | awk '{print $1}')
      img_sum=$(docker compose -f ../docker-compose.yml run --rm -T deck \
                  sh -c "cd /usr/local/bin && cat $names" 2>/dev/null |
                shasum | awk '{print $1}')
      if [ "$host_sum" != "$img_sum" ]; then
        echo "the image's scripts/ differ from the working tree." >&2
        echo "integration tests would run against stale code. Run:  ./deck build" >&2
        exit 1
      fi
    fi ;;
esac

echo ">> bats $("$BATS" --version | awk '{print $2}')  suites: ${dirs[*]}"
exec "$BATS" --print-output-on-failure --recursive "${dirs[@]}"
