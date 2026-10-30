#!/usr/bin/env python3
"""Refresh the BLS/BEA calendar, or check for a release or next-day follow-up."""

# Adapted from Economic/realtalk at 577c812073f10b31d5380ac0fc7719befaee93f0.
# Copyright (c) 2023 realtalk authors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import argparse
from datetime import datetime, time, timedelta, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


EASTERN = ZoneInfo("America/New_York")
# Keep this in sync with scheduled-data-update.yml. The tests check both.
BUILD_TIME = time(14, 27)
UNAVAILABLE = "**Next scheduled update:** unavailable. Run Calendar refresh."
BLS_URL = "https://www.bls.gov/schedule/news_release/bls.ics"
BEA_URL = "https://apps.bea.gov/API/signup/release_dates.json"
RELEASES = {
    "Employment Situation": "bls",
    "Productivity and Costs": "bls",
    "Consumer Price Index": "bls",
    "Gross Domestic Product": "bea",
    "Personal Income and Outlays": "bea",
}


def download(url):
    headers = {"User-Agent": "Mozilla/5.0", "Accept": "*/*"}
    if url == BLS_URL:
        email = os.environ.get("BLS_DOWNLOAD_EMAIL", "").strip()
        if not email:
            raise ValueError("Set BLS_DOWNLOAD_EMAIL to a contact email for BLS calendar downloads.")
        # The browser User-Agent returns 403 on GitHub; a contact email succeeds.
        headers["User-Agent"] = f"productivity-pay-gap calendar {email}"
    request = Request(url, headers=headers)
    try:
        with urlopen(request, timeout=30) as response:
            return response.read().decode("utf-8-sig")
    except OSError as error:
        raise OSError(f"Could not download {url}: {error}") from error


def parse_timestamp(value):
    stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if stamp.utcoffset() is None:
        raise ValueError(f"Release timestamp has no timezone: {value}")
    return stamp.astimezone(timezone.utc)


def bls_events(text):
    """Read the event properties used by BLS, including folded ICS lines."""
    lines = []
    for line in text.splitlines():
        if line.startswith((" ", "\t")) and lines:
            lines[-1] += line[1:]
        else:
            lines.append(line)
    if not lines or lines[0] != "BEGIN:VCALENDAR" or lines[-1] != "END:VCALENDAR":
        raise ValueError("BLS did not return a complete iCalendar file.")

    events = []
    event = None
    for line in lines:
        if line == "BEGIN:VEVENT":
            event = {}
        elif line == "END:VEVENT":
            if event is None:
                raise ValueError("BLS calendar has an unmatched event ending.")
            release = event.get("SUMMARY", (None, ""))[1]
            if RELEASES.get(release) == "bls" and event.get(
                "STATUS", (None, "")
            )[1] != "CANCELLED":
                properties, value = event["DTSTART"]
                stamp = datetime.strptime(value.rstrip("Z"), "%Y%m%dT%H%M%S")
                if value.endswith("Z"):
                    stamp = stamp.replace(tzinfo=timezone.utc)
                else:
                    tzid = properties.get("TZID", "").strip('"')
                    # This is the name of BLS's embedded Eastern VTIMEZONE.
                    zone = "America/New_York" if tzid == "US-Eastern" else tzid
                    if not zone:
                        raise ValueError(f"BLS {release} release has no timezone.")
                    stamp = stamp.replace(tzinfo=ZoneInfo(zone))
                events.append(("bls", release, stamp.astimezone(timezone.utc)))
            event = None
        elif event is not None:
            key, separator, value = line.partition(":")
            if separator:
                name, *parameters = key.split(";")
                properties = dict(parameter.split("=", 1) for parameter in parameters)
                event[name] = (properties, value)
    if event is not None:
        raise ValueError("BLS calendar has an unfinished event.")
    return events


def bea_events(text):
    feed = json.loads(text)
    events = []
    for release, source in RELEASES.items():
        if source != "bea":
            continue
        for value in feed[release]["release_dates"]:
            events.append(("bea", release, parse_timestamp(value)))
    return events


def validate_schedule(schedule, now):
    parse_timestamp(schedule["refreshed_at"])
    events = []
    for event in schedule["events"]:
        if event["release"] not in RELEASES or RELEASES[event["release"]] != event["source"]:
            raise ValueError("Saved calendar contains an unrecognized release.")
        events.append((event["release"], parse_timestamp(event["at"])))
    yesterday = now.astimezone(EASTERN).date() - timedelta(days=1)
    for release in RELEASES:
        # The last event remains usable through its next-day follow-up.
        if not any(name == release and stamp.astimezone(EASTERN).date() >= yesterday for name, stamp in events):
            raise ValueError(
                f"Calendar has no upcoming {release} release or next-day follow-up. Run Calendar refresh."
            )
    return events


def build_schedule(bls_text, bea_text, now):
    yesterday = now.astimezone(EASTERN).date() - timedelta(days=1)
    events = sorted(
        {
            (source, release, stamp)
            for source, release, stamp in bls_events(bls_text) + bea_events(bea_text)
            # A refresh between a release and its follow-up must keep the release.
            if stamp.astimezone(EASTERN).date() >= yesterday
        },
        key=lambda event: (event[2], event[1]),
    )
    schedule = {
        "refreshed_at": now.astimezone(timezone.utc).isoformat(),
        "events": [
            {"source": source, "release": release, "at": stamp.isoformat()}
            for source, release, stamp in events
        ],
    }
    validate_schedule(schedule, now)
    return schedule


def refresh(output, now):
    schedule = build_schedule(download(BLS_URL), download(BEA_URL), now)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Keep an existing schedule intact if either feed or its validation fails.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent, delete=False) as handle:
        temporary = Path(handle.name)
        json.dump(schedule, handle, indent=2)
        handle.write("\n")
    temporary.replace(output)


def due(schedule, now):
    events = validate_schedule(schedule, now)
    today = now.astimezone(EASTERN).date()
    yesterday = today - timedelta(days=1)
    return any(
        yesterday <= stamp.astimezone(EASTERN).date() <= today and stamp <= now
        for _, stamp in events
    )


def next_update(schedule, now):
    """Describe the next future daily slot that the saved calendar makes due."""
    events = validate_schedule(schedule, now)
    builds = {}
    for release, stamp in events:
        release_day = stamp.astimezone(EASTERN).date()
        for offset in (0, 1):
            at = datetime.combine(release_day + timedelta(days=offset), BUILD_TIME, EASTERN)
            # Match due(): a release after the daily check only gets a follow-up.
            if at <= now or stamp > at:
                continue
            reason = f"next-day follow-up for {release}" if offset else f"{release} release"
            builds.setdefault(at, set()).add(reason)
    if not builds:
        return UNAVAILABLE
    at = min(builds)
    # The daily gate validates all five release types before starting any build.
    validate_schedule(schedule, at)
    reasons = sorted(builds[at])
    if len(reasons) == 1:
        reason = reasons[0]
    elif len(reasons) == 2:
        reason = " and ".join(reasons)
    else:
        reason = ", ".join(reasons[:-1]) + ", and " + reasons[-1]
    stamp = f"{at:%B} {at.day}, {at.year}, {at:%-I:%M %p %Z}"
    return f"**Next scheduled update:** {stamp}, {reason}."


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    refresh_parser = commands.add_parser("refresh", help="Download and validate both agency calendars")
    refresh_parser.add_argument("--output", required=True)
    due_parser = commands.add_parser("due", help="Print true on a release day or its next day, otherwise false")
    due_parser.add_argument("schedule")
    next_parser = commands.add_parser("next", help="Describe the next scheduled data build")
    next_parser.add_argument("schedule", nargs="?", help="Saved JSON file; defaults to origin/calendar:schedule.json")
    args = parser.parse_args()
    now = datetime.now(timezone.utc)
    try:
        if args.command == "refresh":
            refresh(args.output, now)
        elif args.command == "due":
            schedule = json.loads(Path(args.schedule).read_text(encoding="utf-8"))
            print("true" if due(schedule, now) else "false")
        else:
            saved = Path(args.schedule).read_text(encoding="utf-8") if args.schedule else subprocess.check_output(
                ["git", "show", "origin/calendar:schedule.json"], text=True, stderr=subprocess.PIPE,
            )
            print(next_update(json.loads(saved), now))
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Calendar error: {error}", file=sys.stderr)
        if args.command == "next":
            print(UNAVAILABLE)
            return 0
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
