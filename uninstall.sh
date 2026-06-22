#!/usr/bin/env bash
#
# uninstall.sh — remove the ticket-to-calendar cron job and its helper scripts.
#
set -uo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SCRIPTS_DST="$HERMES_HOME/scripts"
JOB_NAME="${JOB_NAME:-ticket-to-calendar}"
JOBID_FILE="$SCRIPTS_DST/.${JOB_NAME}.jobid"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

if [ -f "$JOBID_FILE" ]; then
  JOBID="$(cat "$JOBID_FILE")"
  if hermes cron remove "$JOBID" >/dev/null 2>&1; then ok "removed cron job $JOBID"
  else warn "job $JOBID not found (already gone?)"; fi
  rm -f "$JOBID_FILE"
else
  warn "no saved job id ($JOBID_FILE). Remove manually with: hermes cron list / hermes cron remove <id>"
fi

rm -f "$SCRIPTS_DST/ticket_precheck.sh" \
      "$SCRIPTS_DST/set_event_color.py" \
      "$SCRIPTS_DST/${JOB_NAME}.prompt.txt" \
  && ok "removed helper scripts and rendered prompt from $SCRIPTS_DST"

printf '\n  Note: your calendar events and emails are untouched.\n'
