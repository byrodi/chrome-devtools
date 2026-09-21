#!/usr/bin/env bash
# Keeps a random interval between page loads on one site and counts how many
# times that site was loaded during the current browsing session.
#
#   throttle.sh [host-or-url]
#
# Without a host it reuses the host of the previous call (reload, back,
# forward). Local targets (localhost, loopback, private addresses, file:,
# chrome: and similar) pass without a wait. Subdomains share the counter of
# their site, so shop.example.com and www.example.com count as example.com.
#
# Before each load the script picks a random interval between THROTTLE_MIN and
# THROTTLE_MAX seconds (default 1 and 5) and waits until that much time has
# passed since the previous load of the site.
#
# Prints "<site> hits=<N> waited=<S>s". When hits exceed THROTTLE_BUDGET
# (default 25) it prints a warning to stderr and exits with 3: stop and ask the
# human. The counter starts over after THROTTLE_IDLE_RESET seconds without a
# hit (default 1800). State lives in ${TMPDIR:-/tmp}/chrome-devtools-throttle,
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

min="${THROTTLE_MIN:-1}"
max="${THROTTLE_MAX:-5}"
budget="${THROTTLE_BUDGET:-25}"
idle_reset="${THROTTLE_IDLE_RESET:-1800}"
is_uint "$min" || die "THROTTLE_MIN must be a whole number of seconds, got '$min'"
is_uint "$max" || die "THROTTLE_MAX must be a whole number of seconds, got '$max'"
is_uint "$budget" || die "THROTTLE_BUDGET must be a whole number, got '$budget'"
is_uint "$idle_reset" || die "THROTTLE_IDLE_RESET must be a whole number, got '$idle_reset'"
[ "$min" -le "$max" ] || die "THROTTLE_MIN ($min) is greater than THROTTLE_MAX ($max)"

state="${TMPDIR:-/tmp}"
state="${state%/}/chrome-devtools-throttle"
mkdir -p "$state" || die "cannot create state directory $state"

target="${1:-}"
if [ -z "$target" ]; then
  [ -f "$state/_last" ] || die 'no host given and no previous host recorded'
  read -r target < "$state/_last"
fi

target="$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')"
case "$target" in
  file:* | chrome:* | chrome-error:* | about:* | data:* | blob:* | devtools:* | chrome-extension:*)
    printf '%s skipped (local)\n' "${target%%:*}"
    exit 0
    ;;
esac

# Accept a full URL as well as a bare host.
host="${target#*://}"
host="${host%%/*}"
host="${host%%\?*}"
host="${host##*@}"
case "$host" in
  \[*) host="${host%%]*}]" ;;
  *) host="${host%%:*}" ;;
esac
[ -n "$host" ] || die "cannot extract a host from '$target'"

case "$host" in
  localhost | *.localhost | *.local | 127.* | 0.0.0.0 | \[::1\] | 10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[01].*)
    printf '%s skipped (local)\n' "$host"
    exit 0
    ;;
esac

printf '%s\n' "$host" > "$state/_last" || die "cannot write $state/_last"

# Group subdomains under the site: the last two labels, or the last three
# when the second level is a generic one such as co.uk or com.au.
site="$host"
case "$host" in
  \[*) ;;
  *[!0-9.]*)
    IFS=. read -r -a labels <<< "$host"
    n=${#labels[@]}
    if [ "$n" -ge 3 ]; then
      case "${labels[n-2]}" in
        co | com | net | org | gov | edu | ac) keep=3 ;;
        *) keep=2 ;;
      esac
      [ "${#labels[n-1]}" -eq 2 ] || keep=2
      site="${labels[*]:n-keep}"
      site="${site// /.}"
    fi
    ;;
esac

file="$state/${site//[^a-z0-9._-]/_}"

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

span_ms=$(( (max - min) * 1000 ))
interval_ms=$(( min * 1000 + (RANDOM * 32768 + RANDOM) % (span_ms + 1) ))
wait_ms=$(( interval_ms - gap * 1000 ))
[ "$wait_ms" -lt 0 ] && wait_ms=0
waited="$(printf '%d.%03d' $(( wait_ms / 1000 )) $(( wait_ms % 1000 )))"
[ "$wait_ms" -gt 0 ] && sleep "$waited"

hits=$(( hits + 1 ))
printf '%s %s\n' "$(date +%s)" "$hits" > "$file" || die "cannot write $file"
printf '%s hits=%s waited=%ss\n' "$site" "$hits" "$waited"

if [ "$hits" -gt "$budget" ]; then
  printf 'WARNING: %s loaded %s times this session (budget %s). Stop browsing it and ask the human.\n' \
    "$site" "$hits" "$budget" >&2
  exit 3
fi
exit 0
