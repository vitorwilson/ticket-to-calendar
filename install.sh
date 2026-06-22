#!/usr/bin/env bash
#
# install.sh — set up the "ticket-to-calendar" Hermes cron job on this machine.
#
# Run this ON the box where Hermes is installed. It verifies prerequisites,
# asks a few config questions (or reads them from env vars), renders the prompt
# template, deploys the helper scripts into $HERMES_HOME/scripts/, and creates
# (or updates) the hourly cron job.
#
# Non-interactive use: pre-set any of these env vars to skip the prompt —
#   TIMEZONE, HOME_CITY, DELIVER, SCHEDULE, JOB_NAME
#
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SCRIPTS_DST="$HERMES_HOME/scripts"
GAPI="python $HERMES_HOME/skills/productivity/google-workspace/scripts/google_api.py"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
hdr "1. Checking prerequisites"

command -v hermes >/dev/null 2>&1 || die "hermes CLI not found on PATH. Install Hermes first."
ok "hermes CLI found"

[ -f "$HERMES_HOME/skills/productivity/google-workspace/scripts/google_api.py" ] \
  || die "google-workspace skill not found. Install it (it ships with Hermes) and authorize Google."
ok "google-workspace skill present"

[ -f "$HERMES_HOME/skills/productivity/maps/scripts/maps_client.py" ] \
  || die "maps skill not found. Install it (it ships with Hermes)."
ok "maps skill present"

# Google auth — list today's events as a smoke test.
TODAY="$(date +%F)"
if $GAPI calendar list --start "${TODAY}T00:00:00Z" --end "${TODAY}T23:59:59Z" >/dev/null 2>&1; then
  ok "Google Calendar auth works"
else
  die "Google auth failed. Run: python $HERMES_HOME/skills/productivity/google-workspace/scripts/setup.py"
fi

# Cron-platform toolsets (best effort — needs a TTY).
if hermes tools list --platform cron >/tmp/_tk_tools 2>/dev/null; then
  for t in web terminal skills; do
    if grep -qE "enabled[[:space:]]+$t\b" /tmp/_tk_tools; then ok "cron toolset '$t' enabled"
    else warn "cron toolset '$t' is NOT enabled — run 'hermes tools' and enable it for the cron platform"; fi
  done
  rm -f /tmp/_tk_tools
else
  warn "Could not read cron toolsets (needs a terminal). Ensure web + terminal + skills are enabled for the cron platform via 'hermes tools'."
fi

# ---------------------------------------------------------------------------
hdr "2. Configuration"

ask() { # ask <varname> <prompt> <default>
  local var="$1" prompt="$2" def="$3" cur
  cur="${!var:-}"
  if [ -n "$cur" ]; then printf '  %s = %s (from env)\n' "$var" "$cur"; return; fi
  read -r -p "  $prompt [$def]: " ans </dev/tty
  printf -v "$var" '%s' "${ans:-$def}"
}

ask TIMEZONE "IANA timezone for your events" "America/Sao_Paulo"
ask HOME_CITY "Your city (used to geocode venue names)" "Rio de Janeiro"
ask DELIVER  "Delivery target (telegram/discord/signal/local/platform:chat_id)" "telegram"
ask SCHEDULE "Cron schedule" "0 * * * *"
ask JOB_NAME "Job name" "ticket-to-calendar"

# Validate timezone.
if ! TZ="$TIMEZONE" date >/dev/null 2>&1; then
  die "Timezone '$TIMEZONE' is not recognized by this system (check /usr/share/zoneinfo)."
fi
ok "timezone '$TIMEZONE' valid ($(TZ="$TIMEZONE" date +%:z) right now)"

# ---------------------------------------------------------------------------
hdr "3. Deploying scripts"

mkdir -p "$SCRIPTS_DST"
install -m 0755 "$REPO_DIR/scripts/ticket_precheck.sh" "$SCRIPTS_DST/ticket_precheck.sh"
install -m 0755 "$REPO_DIR/scripts/set_event_color.py" "$SCRIPTS_DST/set_event_color.py"
ok "installed ticket_precheck.sh and set_event_color.py into $SCRIPTS_DST"

# Render the prompt template.
PROMPT_FILE="$SCRIPTS_DST/${JOB_NAME}.prompt.txt"
python3 - "$REPO_DIR/cron_prompt.template.txt" "$PROMPT_FILE" "$TIMEZONE" "$HOME_CITY" <<'PY'
import sys
src, dst, tz, city = sys.argv[1:5]
text = open(src).read().replace("{{TIMEZONE}}", tz).replace("{{HOME_CITY}}", city)
open(dst, "w").write(text)
PY
ok "rendered prompt -> $PROMPT_FILE"

# ---------------------------------------------------------------------------
hdr "4. Creating the cron job"

JOBID_FILE="$SCRIPTS_DST/.${JOB_NAME}.jobid"
# Remove an existing install of this job (by saved id) so re-running is clean.
if [ -f "$JOBID_FILE" ]; then
  OLDID="$(cat "$JOBID_FILE")"
  if hermes cron list 2>/dev/null | grep -q "$OLDID"; then
    hermes cron remove "$OLDID" >/dev/null 2>&1 && warn "removed previous job $OLDID"
  fi
fi

CREATE_OUT="$(hermes cron create "$SCHEDULE" "$(cat "$PROMPT_FILE")" \
  --skill google-workspace --skill maps \
  --script ticket_precheck.sh \
  --name "$JOB_NAME" \
  --deliver "$DELIVER" 2>&1)"
echo "$CREATE_OUT" | sed 's/^/  /'

NEWID="$(printf '%s\n' "$CREATE_OUT" | grep -oE 'Created job: [0-9a-f]+' | awk '{print $3}')"
if [ -n "$NEWID" ]; then
  echo "$NEWID" > "$JOBID_FILE"
  ok "job created: $NEWID (saved to $JOBID_FILE)"
else
  die "Could not parse new job id from 'hermes cron create' output above."
fi

# ---------------------------------------------------------------------------
hdr "Done."
cat <<EOF

  The job runs on schedule: $SCHEDULE  (delivery: $DELIVER)
  It stays silent unless it adds a new event.

  Test it now without waiting:
    hermes cron run $NEWID >/dev/null; hermes cron tick
    ls -t $HERMES_HOME/cron/output/$NEWID/ | head -1

  Reconfigure the prompt later:
    edit $PROMPT_FILE, then
    hermes cron edit $NEWID --prompt "\$(cat $PROMPT_FILE)"

  Uninstall:
    ./uninstall.sh
EOF
