#!/usr/bin/env bash
# Pre-check gate for the ticket-to-calendar cron job.
#
# Runs the SAME 90-minute Gmail query the agent uses (STEP 2 of the prompt).
# - Window genuinely empty   -> print {"wakeAgent": false} as the last line so
#   Hermes skips the agent run entirely: no LLM calls, no quota burn, no delivery.
# - Any messages present      -> print them as context and wake the agent normally.
# - Search errors / uncertain -> FAIL OPEN (wake the agent) so a transient Gmail
#   hiccup can never silently drop a real ticket.
#
# Hermes only treats a final-line literal {"wakeAgent": false} as "skip"; any
# other output (text, missing key, true) wakes the agent.

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
GAPI="python $HERMES_HOME/skills/productivity/google-workspace/scripts/google_api.py"
SINCE=$(date -d '90 minutes ago' +%s)
ERR=$(mktemp 2>/dev/null || echo /tmp/ticket_precheck.err)

RESULTS=$($GAPI gmail search "after:$SINCE -in:spam -in:trash" --max 50 2>"$ERR")
RC=$?

if [ $RC -ne 0 ]; then
  # Search failed — fail OPEN so we never miss a ticket on a transient error.
  echo "PRECHECK: gmail search failed (rc=$RC) — waking agent to be safe."
  echo "--- stderr ---"
  cat "$ERR" 2>/dev/null
  exit 0
fi

if printf '%s' "$RESULTS" | grep -q '"id"'; then
  # Candidate email(s) in the window — hand them to the agent as context.
  echo "## Recent mail in the 90-minute window (collected by pre-check):"
  printf '%s\n' "$RESULTS"
  echo "PRECHECK: candidate email(s) found — waking agent to triage."
  exit 0
fi

# Search succeeded and the window is genuinely empty → skip the agent entirely.
echo '{"wakeAgent": false}'
