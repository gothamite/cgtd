#!/usr/bin/env bash
# Per-install cron logging helper. State under $CGTD_DATA_DIR.
# Usage: cron-log.sh start <cron_id>           -> prints RID
#        cron-log.sh ok <RID>
#        cron-log.sh fail <RID> "<message>"
#        cron-log.sh lock <cron_id>            -> exit 0 if acquired, 1 if held
#        cron-log.sh pending                   -> RIDs in 'started' >15 min
#        cron-log.sh last-ok <cron_id>         -> ISO ts of last ok, empty if none
#        cron-log.sh prune                     -> trim log to last 1000 lines

set -euo pipefail

DATA="${CGTD_DATA_DIR:-/data}"
LOG="$DATA/cron-log.jsonl"
LOCK_DIR="$DATA/lock"
mkdir -p "$LOCK_DIR"
touch "$LOG"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

case "${1:-}" in
  start)
    cron_id="${2:?}"
    rid="$(now)-$cron_id-$$"
    printf '{"rid":"%s","cron_id":"%s","state":"started","ts":"%s"}\n' "$rid" "$cron_id" "$(now)" >> "$LOG"
    echo "$rid"
    ;;
  ok)
    rid="${2:?}"
    printf '{"rid":"%s","state":"ok","ts":"%s"}\n' "$rid" "$(now)" >> "$LOG"
    "$0" prune
    ;;
  fail)
    rid="${2:?}"; msg="${3:-error}"
    printf '{"rid":"%s","state":"fail","ts":"%s","msg":%s}\n' \
      "$rid" "$(now)" "$(printf '%s' "$msg" | jq -Rs .)" >> "$LOG"
    ;;
  lock)
    cron_id="${2:?}"
    lock="$LOCK_DIR/$cron_id.lock"
    exec 9>"$lock"
    flock -n 9 || exit 1
    ;;
  pending)
    cutoff="$(date -u -d '15 min ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -v-15M +%Y-%m-%dT%H:%M:%SZ)"
    jq -r --arg c "$cutoff" \
      'select(.state=="started" and .ts < $c) | .rid' "$LOG"
    ;;
  last-ok)
    cron_id="${2:?}"
    jq -r --arg c "$cron_id" '
      select(.state=="ok") |
      .rid as $r | $r | capture("(?<ts>[^-]+-[^-]+-[^-]+Z)-(?<id>.+)-[0-9]+$") |
      select(.id==$c) | .ts' "$LOG" | tail -1
    ;;
  prune)
    tail -1000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    ;;
  *)
    echo "usage: $0 {start|ok|fail|lock|pending|last-ok|prune} ..." >&2
    exit 2
    ;;
esac
