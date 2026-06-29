# ticket-to-calendar

A small [Hermes](https://github.com/NousResearch/hermes-agent) automation that
watches your inbox for **event ticket confirmations** and quietly adds them to
your Google Calendar — with the venue address looked up, a sensible end time,
and a color by event type. It only pings you when it actually adds something.

Buy a concert ticket on Sympla / Eventim / Ticketmaster / Eventbrite / a cinema
site → an hour later the event is on your calendar, at the right place, colored
Tangerine. No copy-pasting.

> Built for [Hermes](https://github.com/NousResearch/hermes-agent). The logic
> (the prompt + the two helper scripts) is portable; the plumbing — scheduler,
> Gmail/Calendar access, delivery — rides on Hermes. See
> [Porting](#porting-to-another-setup) if you want to adapt it elsewhere.

## What it does

- **Hourly inbox scan** for ticket confirmation emails (judged by content, not a
  fixed sender list — works with vendors worldwide).
- **Creates the calendar event** with the correct date/time for your timezone
  (DST-aware), no confirmation needed.
- **Resolves the venue** to a real street address via the `maps` skill when the
  email only gives a venue name.
- **Estimates the end time** when the ticket doesn't state one — looks up film
  runtimes / show lengths, falls back to 2h30 for concerts.
- **Color-codes by type**: concert → Tangerine, cinema → Blueberry, theatre →
  Grape, sports → Basil, festival → Banana, other → Sage.
- **Deduplicates**: re-running never creates a second copy of an event that's
  already on your calendar.
- **Stays quiet**: if nothing new was added, it sends no message.
- **Quota-friendly**: a pre-check gate skips the LLM entirely on hours with no
  new mail, so empty hours cost ~nothing.

## Requirements

A working **Hermes** install on the machine you'll run this on, with:

- the **google-workspace** skill installed **and Google OAuth authorized**
  (run its `setup.py` once);
- the **maps** skill installed;
- the **cron platform** toolsets `terminal`, `web`, and `skills` enabled
  (`hermes tools` → cron platform);
- a delivery channel configured (Telegram, Discord, Signal, …) if you want the
  "added an event" pings.

Both skills ship with Hermes. The installer checks all of the above and tells
you exactly what's missing.

## Install

```bash
git clone https://github.com/vitorwilson/ticket-to-calendar.git
cd ticket-to-calendar
./install.sh
```

The installer asks for (or reads from env vars):

| Setting     | Default              | Meaning                                        |
|-------------|----------------------|------------------------------------------------|
| `TIMEZONE`  | `America/Sao_Paulo`  | IANA timezone your events are in (DST-aware).  |
| `HOME_CITY` | `Rio de Janeiro`     | City appended when geocoding bare venue names. |
| `DELIVER`   | `telegram`           | Where "added an event" messages go.            |
| `SCHEDULE`  | `0 * * * *`          | Cron schedule (hourly by default).             |
| `JOB_NAME`  | `ticket-to-calendar` | Hermes job name.                               |

Non-interactive:

```bash
TIMEZONE="Europe/Berlin" HOME_CITY="Berlin" DELIVER="discord" ./install.sh
```

### Test it immediately

```bash
hermes cron run <job-id> >/dev/null; hermes cron tick
ls -t ~/.hermes/cron/output/<job-id>/ | head -1   # newest run transcript
```

(The `run` + `tick` pairing is the reliable way to force a run between scheduled
ticks — `run` on its own may wait for the next hour.)

## How it works

```
        ┌─ every hour ────────────────────────────────────────────────┐
        │                                                             │
   ticket_precheck.sh  ──►  any mail in the last 90 min?              │
        │                      │ no  → {"wakeAgent": false} → STOP    │
        │                      │ yes → wake the agent ▼               │
        │                                                             │
   Hermes agent (google-workspace + maps skills)                      │
     1. gmail search (last 90 min)                                    │
     2. read candidate bodies, keep real ticket confirmations         │
     3. dedupe against the calendar for that day                      │
     4. fill gaps: venue address (maps), end time (web)               │
     5. calendar create  →  set_event_color.py (color by type)        │
     6. report new events, or stay [SILENT]                           │
        └─────────────────────────────────────────────────────────────┘
```

- **`scripts/ticket_precheck.sh`** runs before the agent each tick. Empty window
  → it prints `{"wakeAgent": false}` and Hermes skips the agent (zero LLM cost).
  It **fails open**: on any Gmail error it wakes the agent rather than risk
  dropping a ticket.
- **`scripts/set_event_color.py`** sets a calendar event's `colorId` (the skill's
  `calendar create` has no color flag). It reuses the google-workspace skill's
  OAuth but lives outside the skill, so `hermes skills update` won't touch it.
- **`cron_prompt.template.txt`** is the agent's instructions; `install.sh`
  renders your `TIMEZONE` / `HOME_CITY` into it and stores the result at
  `~/.hermes/scripts/<job-name>.prompt.txt`.

## Customizing

- **Colors / categories**: edit STEP 6b in `cron_prompt.template.txt`
  (colorIds are 1–11; see the table in the prompt), then re-run `./install.sh`.
- **End-time rules, vendor hints, window size**: edit the template and re-install.
- **Just the prompt on a live job**: edit `~/.hermes/scripts/<job>.prompt.txt`
  and run `hermes cron edit <id> --prompt "$(cat <that file>)"`.

## Troubleshooting

- **Runs fail with `HTTP 429 RESOURCE_EXHAUSTED`** — your Hermes LLM backend is on
  a rate-limited free tier (e.g. Gemini free tier, 20 req). Switch the model in
  your Hermes config. The pre-check gate reduces how often the agent runs but
  can't eliminate this on busy hours.
- **Events land at the wrong hour** — your `TIMEZONE` is off. Re-run the
  installer with the correct IANA zone.
- **No Telegram/Discord ping** — confirm a delivery channel is set up in Hermes
  and that `DELIVER` matches it. Remember: it's silent by design when nothing new
  was added.
- **Inspect any run**: `~/.hermes/cron/output/<job-id>/<timestamp>.md`. Gated
  (skipped) ticks just say `Script gate returned wakeAgent=false — agent skipped`.
- **Google auth fails (`TOKEN_REVOKED` / `REFRESH_FAILED`)** — re-authorize with
  `python ~/.hermes/skills/productivity/google-workspace/scripts/setup.py --auth-url`,
  follow the OAuth flow, then verify with `--check-live`. Re-run `./install.sh`
  afterward (or just `hermes cron run <id> >/dev/null; hermes cron tick` to test).
- **Auth dies every ~7 days** — your Google Cloud OAuth app is in "Testing"
  publishing status. Google expires refresh tokens after 7 days in Testing mode.
  Fix: go to <https://console.cloud.google.com/auth/audience>, set the consent
  screen to "In production", and confirm. No Google verification review is needed
  for a personal-use Desktop app — you'll see a one-time "Google hasn't verified
  this app" warning, which is fine. After publishing, the refresh token stops
  expiring on the 7-day clock.

## Uninstall

```bash
./uninstall.sh
```

Removes the cron job and the helper scripts. Your calendar and email are
untouched.

## Porting to another setup

The portable parts are `cron_prompt.template.txt` (the logic) and the two
scripts in `scripts/`. What's tied to Hermes — and what you'd swap it for — is
listed in [AGENTS.md](AGENTS.md#porting-to-a-non-hermes-setup).

## Status

A personal side project, shared in case it's useful. Not actively seeking
contributions. See [CHANGELOG.md](CHANGELOG.md) for changes.

## License

MIT — see [LICENSE](LICENSE).
