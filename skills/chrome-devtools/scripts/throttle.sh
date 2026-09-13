#!/usr/bin/env bash
# Keeps a minimum interval between page loads on one host and counts how many
# times that host was loaded during the current browsing session.
#
#   throttle.sh <host-or-url> [min_seconds]
#
# Prints "<host> hits=<N> waited=<S>s". When hits exceed THROTTLE_BUDGET
# (default 25) it also prints a warning to stderr: stop and ask the human.
# The counter starts over after THROTTLE_IDLE_RESET seconds without a hit
# (default 1800). State lives in ${TMPDIR:-/tmp}/chrome-devtools-throttle,
# so the script does not depend on the working directory.

set -u

die() {
  printf 'throttle.sh: %s\n' "$1" >&2
  exit 2
}

is_uint() {
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
  esac
}

[ $# -ge 1 ] && [ -n "$1" ] || die 'usage: throttle.sh <host-or-url> [min_seconds]'

min="${2:-8}"
budget="${THROTTLE_BUDGET:-25}"
idle_reset="${THROTTLE_IDLE_RESET:-1800}"
is_uint "$min" || die "min_seconds must be a whole number of seconds, got '$min'"
is_uint "$budget" || die "THROTTLE_BUDGET must be a whole number, got '$budget'"
is_uint "$idle_reset" || die "THROTTLE_IDLE_RESET must be a whole number, got '$idle_reset'"

# Accept a full URL as well as a bare host, so www.ozon.ru and
# https://ozon.ru/product/... share one counter.
host="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
host="${host#*://}"
host="${host%%/*}"
host="${host%%\?*}"
host="${host%%:*}"
host="${host#www.}"
[ -n "$host" ] || die "cannot extract a host from '$1'"

state="${TMPDIR:-/tmp}"
state="${state%/}/chrome-devtools-throttle"
mkdir -p "$state" || die "cannot create state directory $state"
file="$state/${host//[^a-z0-9._-]/_}"

last=0
hits=0
if [ -f "$file" ]; then
  read -r last hits < "$file"
  is_uint "$last" || last=0
  is_uint "$hits" || hits=0
fi

gap=$(( $(date +%s) - last ))
[ "$gap" -lt 0 ] && gap=0
[ "$gap" -gt "$idle_reset" ] && hits=0

waited=0
if [ "$gap" -lt "$min" ]; then
  waited=$(( min - gap ))
  sleep "$waited"
fi

hits=$(( hits + 1 ))
printf '%s %s\n' "$(date +%s)" "$hits" > "$file" || die "cannot write $file"
printf '%s hits=%s waited=%ss\n' "$host" "$hits" "$waited"

if [ "$hits" -gt "$budget" ]; then
  printf 'WARNING: %s loaded %s times this session (budget %s). Stop browsing it and ask the human.\n' \
    "$host" "$hits" "$budget" >&2
fi
exit 0
