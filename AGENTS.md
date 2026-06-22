# AGENTS.md

Guidance for AI coding agents (and humans) working on this repository.

## What this project is

A distributable installer for a **Hermes cron job** ("ticket-to-calendar") that scans Gmail for ticket-confirmation emails and auto-creates Google Calendar events: address resolved via the `maps` skill, end time estimated, color-coded by type, deduplicated, silent when nothing new. It targets people running **Hermes**; machine-specific values (timezone, city, delivery, schedule) are parametrized by the installer, not hardcoded.

This is intentionally Hermes-specific (see "Porting" below for what's tied to Hermes and what isn't). It is not a multi-agent abstraction — there is one backend, done well.

## Repo layout

| File | Role |
|---|---|
| `install.sh` | Checks prerequisites, collects config, renders the prompt, deploys scripts, creates the cron job. Entry point. |
| `uninstall.sh` | Removes the job (via the saved id) and the deployed scripts. |
| `cron_prompt.template.txt` | The agent's instructions, with `{{TIMEZONE}}` / `{{HOME_CITY}}` placeholders. |
| `scripts/ticket_precheck.sh` | Pre-run wake-gate. Deployed to `$HERMES_HOME/scripts/`. |
| `scripts/set_event_color.py` | Sets a calendar event's `colorId`. Deployed to `$HERMES_HOME/scripts/`. |
| `README.md` | User-facing docs. |
| `CHANGELOG.md` | Keep a Changelog format. |

`cron_prompt.txt`, `*.prompt.txt`, and `*.jobid` are gitignored — they are rendered, machine-specific outputs, not source.

## Architecture / things that span files

- **Two scripts, two homes.** The repo's `scripts/*` are *sources*; `install.sh` copies them to `$HERMES_HOME/scripts/` where Hermes and the agent reference them. Editing the deployed copy and the repo copy are different things — change the repo copy and re-run `install.sh`.
- **The prompt is rendered, then stored in the job.** `install.sh` substitutes `{{TIMEZONE}}`/`{{HOME_CITY}}` into the template → `$HERMES_HOME/scripts/<job>.prompt.txt` → passed to `hermes cron create --prompt`. The cron job stores its **own copy** of the prompt; editing the template later requires re-rendering and `hermes cron edit <id> --prompt ...` (or re-running `install.sh`). Editing the template alone changes nothing live.
- **Wake-gate contract** (`ticket_precheck.sh`): Hermes reads the script's **last non-empty stdout line**; only a literal `{"wakeAgent": false}` skips the agent (no LLM, no delivery). Anything else wakes it, and the script's stdout is injected into the prompt as context. The script **fails open** — only emits the skip on a *successful* empty search, never on error, so a transient Gmail hiccup can't drop a ticket.
- **Color path** (`set_event_color.py`): the skill's `calendar create` has no color flag and there's no `update`/`patch` CLI command, so coloring is a separate `events().patch(..., {"colorId": N})` call. The helper imports `build_service` from the google-workspace skill to reuse its OAuth token, but lives outside the skill so `hermes skills update`/`audit` can't clobber it. STEP 6b of the prompt drives it; colorIds are 1–11.
- **Timezone is DST-correct, not a fixed offset.** The prompt tells the agent to compute the offset per event date with `TZ="<zone>" date -d "<date> <time>" +%:z`, so it works in any zone — not just zones without DST.

## Prerequisites the installer enforces

`hermes` on PATH; google-workspace skill + working Google OAuth (smoke-tested with a `calendar list`); maps skill; cron-platform toolsets `terminal`/`web`/`skills`; a delivery channel for pings.

## Testing a live job (operational notes)

- Force a run between scheduled ticks: **`hermes cron run <id> >/dev/null; hermes cron tick`** in one shell. `cron run` alone is unreliable once the gateway has advanced the job's next-run past the current slot (run-state is held in the gateway's memory, not jobs.json).
- Run transcripts: `$HERMES_HOME/cron/output/<job-id>/<timestamp>.md`. The `## Response` section is the final agent message; gated ticks just say `Script gate returned wakeAgent=false — agent skipped`.
- End-to-end test: send a ticket-style email to the authorized account, force a run, confirm the event + its `colorId`, then delete the event and trash the email.

## Porting to a non-Hermes setup

The portable artifacts are **the prompt** (the logic) and **the two helper scripts**. Hermes-specific touchpoints, if someone adapts this elsewhere:

| Touchpoint | Hermes today | Swap for |
|---|---|---|
| Scheduler + wake-gate | `hermes cron` + `{"wakeAgent": false}` | system cron / systemd timer; drop the gate or wrap it |
| Gmail + Calendar | `google-workspace` skill's `google_api.py` | a standalone Google OAuth client |
| Geocoding | `maps` skill's `maps_client.py` | a direct Nominatim/OSM call |
| Reasoning | a Hermes agent run | any agent that shells out + calls an LLM |
| Delivery | Hermes channels | any notifier |

## Backend model / quota note

Cron agent runs use whatever LLM Hermes is configured with. `HTTP 429 RESOURCE_EXHAUSTED` means a rate-limited/free tier — switch the model. The pre-check gate mitigates but does not eliminate this on busy hours.
