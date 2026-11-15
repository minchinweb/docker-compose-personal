#!/usr/bin/env bash
# Validate every live stack (top-level, non-dot dirs) with `docker compose config`.
#
# The real `.env` is gitignored (and hard-linked into each stack dir), so this builds a
# throwaway env file with a placeholder for every ${VAR} the compose files reference and
# passes it with --env-file, which replaces the stack's own `.env`. Safe to run locally.
set -uo pipefail
cd "$(dirname "$0")/.."

env_file=$(mktemp)
trap 'rm -f "$env_file"' EXIT

# ${VAR}, ${VAR:-x}, ${VAR?err}, ... but not $${VAR} (escaped for the container's shell)
grep -ohE '(^|[^$])\$\{[A-Za-z_][A-Za-z0-9_]*' */docker-compose.yaml \
  | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' | sort -u \
  | while read -r var; do
      case "$var" in
        PUID|PGID)                 val=1000 ;;
        *_PORT)                    val=12345 ;;
        *_IP)                      val=192.0.2.1 ;;
        *_DIR|*_DIR_2|*USERDIR|*LOCATION) val=/srv/placeholder ;;
        *VERSION)                  val=latest ;;
        *)                         val=placeholder ;;
      esac
      echo "$var=$val"
    done > "$env_file"

failed=0
for f in */docker-compose.yaml; do
  if out=$(docker compose --env-file "$env_file" -f "$f" config -q 2>&1); then
    echo "ok    $f"
    # surface warnings (e.g. obsolete keys) without failing the run
    [ -n "$out" ] && echo "$out" | sed 's/^/      /'
  else
    echo "FAIL  $f"
    echo "$out" | sed 's/^/      /'
    failed=1
  fi
done
exit $failed
