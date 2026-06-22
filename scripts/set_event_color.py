#!/usr/bin/env python3
"""Set the colorId on an existing Google Calendar event.

Standalone companion to the google-workspace skill. It reuses that skill's
auth (imports build_service / get_credentials via the same OAuth token) but
lives OUTSIDE the bundled skill so `hermes skills update` / `skills audit`
can't clobber or flag it. Used by the ticket-to-calendar cron job to color
events by type after creation, since the skill's `calendar create` exposes no
color flag.

Usage:
  python set_event_color.py <event_id> <colorId> [--calendar primary]

colorId is 1-11 (the Google Calendar event palette). Exits non-zero on bad
input or API failure so the agent can see it failed — the event still exists,
just with the default color (graceful degradation).
"""
import argparse
import json
import os
import sys
from pathlib import Path

# Reuse the google-workspace skill's auth without modifying the skill itself.
_HERMES_HOME = os.environ.get("HERMES_HOME") or str(Path.home() / ".hermes")
_SKILL_SCRIPTS = str(
    Path(_HERMES_HOME) / "skills" / "productivity" / "google-workspace" / "scripts"
)
if _SKILL_SCRIPTS not in sys.path:
    sys.path.insert(0, _SKILL_SCRIPTS)

try:
    from google_api import build_service  # noqa: E402
except ImportError as exc:
    print(json.dumps({
        "status": "error",
        "reason": f"could not import google-workspace skill from {_SKILL_SCRIPTS}: {exc}",
    }))
    sys.exit(1)

VALID_COLOR_IDS = {str(n) for n in range(1, 12)}  # 1..11


def main():
    ap = argparse.ArgumentParser(description="Set colorId on a Google Calendar event.")
    ap.add_argument("event_id")
    ap.add_argument("color_id", help="Google Calendar colorId, 1-11")
    ap.add_argument("--calendar", default="primary")
    args = ap.parse_args()

    if args.color_id not in VALID_COLOR_IDS:
        print(json.dumps({
            "status": "error",
            "reason": f"colorId must be 1-11, got {args.color_id!r}",
        }))
        sys.exit(2)

    try:
        service = build_service("calendar", "v3")
        result = service.events().patch(
            calendarId=args.calendar,
            eventId=args.event_id,
            body={"colorId": args.color_id},
        ).execute()
    except Exception as exc:
        print(json.dumps({"status": "error", "reason": str(exc)}))
        sys.exit(1)

    print(json.dumps({
        "status": "colored",
        "id": result.get("id", args.event_id),
        "colorId": result.get("colorId", args.color_id),
        "summary": result.get("summary", ""),
    }))


if __name__ == "__main__":
    main()
