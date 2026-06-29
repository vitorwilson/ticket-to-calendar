# Changelog

All notable changes to this project are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.1] - 2026-06-29

### Fixed
- `install.sh`: auth failure message now suggests the correct `--auth-url` flag
  (not bare `setup.py`) and warns about the 7-day token expiry for OAuth apps
  in "Testing" publishing status.

### Added
- Troubleshooting entries in README for `TOKEN_REVOKED` / `REFRESH_FAILED` and
  the recurring 7-day expiry root cause (OAuth app in Testing mode).
- `AGENTS.md`: "Google OAuth token lifecycle" section documenting the
  Testing-vs-Production publishing status impact on refresh token longevity.

## [0.1.0] - 2026-06-22

### Added
- Hourly Hermes cron job that scans Gmail for ticket confirmations and creates
  Google Calendar events without confirmation.
- Venue address resolution via the `maps` skill when an email gives only a name.
- End-time estimation (film runtime / show length lookups, 2h30 concert default).
- Color-coding by event type (`scripts/set_event_color.py`), since the skill's
  `calendar create` exposes no color flag.
- Same-event deduplication against the calendar before creating.
- Pre-check wake-gate (`scripts/ticket_precheck.sh`) that skips the LLM on hours
  with no new mail, and fails open on Gmail errors.
- DST-aware timezone handling (computes the offset per event date).
- `install.sh` / `uninstall.sh` with parametrized `TIMEZONE`, `HOME_CITY`,
  `DELIVER`, `SCHEDULE`, `JOB_NAME`.
