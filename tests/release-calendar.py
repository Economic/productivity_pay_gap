"""Offline checks for agency formats and release-day plus next-day builds.

Adapted from Economic/realtalk's calendar tests at 577c812073f10b31d5380ac0fc7719befaee93f0.
"""

from datetime import datetime, timedelta, timezone
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from zoneinfo import ZoneInfo


SCRIPT = Path(__file__).resolve().parents[1] / ".github/scripts/release-calendar.py"
SPEC = importlib.util.spec_from_file_location("release_calendar", SCRIPT)
calendar = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(calendar)
EASTERN = ZoneInfo("America/New_York")
NOW = datetime(2026, 10, 28, 18, 27, tzinfo=timezone.utc)
RELEASES = {
    "Employment Situation": "bls",
    "Productivity and Costs": "bls",
    "Consumer Price Index": "bls",
    "Gross Domestic Product": "bea",
    "Personal Income and Outlays": "bea",
}


def bls_event(release, stamp, extra="", timezone_name="US-Eastern"):
    start = f"DTSTART;TZID={timezone_name}:{stamp}"
    return f"BEGIN:VEVENT\nSUMMARY:{release}\n{start}\n{extra}END:VEVENT\n"


BLS = "BEGIN:VCALENDAR\n" + "".join([
    bls_event("Employment Situation", "20261026T083000"),
    bls_event("Productivity and Costs", "20261105T083000", "DESCRIPTION:Preliminary\n"),
    bls_event("Employment Situation", "20261106T083000"),
    bls_event("Consumer Price In\n dex", "20261110T083000"),
    bls_event("Consumer Price Index", "20261112T083000", "STATUS:CANCELLED\n"),
    bls_event("Producer Price Index", "20261113T083000"),
    bls_event("Productivity and Costs", "20261208T083000", "DESCRIPTION:Revised\n"),
]) + "END:VCALENDAR\n"
BEA = json.dumps({
    release: {"release_dates": [
        "2026-10-29T12:30:00+00:00",
        "2026-10-29T12:30:00+00:00",
        "2026-11-25T13:30:00+00:00",
    ]}
    for release, source in RELEASES.items() if source == "bea"
})


def saved_schedule(stamp, future=True):
    events = [
        {"source": source, "release": release, "at": stamp.isoformat()}
        for release, source in RELEASES.items()
    ]
    if future:
        events += [
            {"source": source, "release": release, "at": "2099-01-01T13:30:00Z"}
            for release, source in RELEASES.items()
        ]
    return {"refreshed_at": NOW.isoformat(), "events": events}


def single_release_schedule(stamp, release="Employment Situation"):
    schedule = saved_schedule(datetime(2099, 1, 1, 8, 30, tzinfo=EASTERN), future=False)
    schedule["events"].append({
        "source": RELEASES[release], "release": release, "at": stamp.isoformat(),
    })
    return schedule


class ReleaseCalendarTests(unittest.TestCase):
    def test_expected_quarter_advances_only_sources_with_a_release_by_next_build(self):
        stamp = datetime(2026, 11, 5, 8, 30, tzinfo=EASTERN)
        for release in RELEASES:
            with self.subTest(release=release):
                schedule = single_release_schedule(stamp, release)
                coverage = dict.fromkeys(RELEASES, 2026 * 4 + 2)  # 2026q3
                coverage[release] -= 1
                original = coverage.copy()
                text = calendar.expected_output_quarter(schedule, stamp, coverage)
                self.assertIn("2026q3 (subject to source availability)", text)
                self.assertEqual(coverage, original)
                # A different lagging source still limits the combined output.
                other = next(name for name in RELEASES if name != release)
                coverage[other] -= 1
                text = calendar.expected_output_quarter(schedule, stamp, coverage)
                self.assertIn("2026q2 (no new quarter expected, subject to source availability)", text)

    def test_follow_up_can_still_catch_delayed_release_data(self):
        stamp = datetime(2026, 11, 5, 8, 30, tzinfo=EASTERN)
        coverage = dict.fromkeys(RELEASES, 2026 * 4 + 2)
        coverage["Productivity and Costs"] -= 1
        schedule = single_release_schedule(stamp, "Productivity and Costs")
        text = calendar.expected_output_quarter(schedule, stamp.replace(hour=15), coverage)
        self.assertIn("2026q3 (subject to source availability)", text)

    def test_monthly_releases_require_three_months_before_advancing_a_quarter(self):
        stamp = datetime(2026, 11, 6, 8, 30, tzinfo=EASTERN)
        for release in ("Employment Situation", "Consumer Price Index"):
            coverage = dict.fromkeys(RELEASES, 2026 * 4 + 3)  # Other inputs through 2026q4
            coverage[release] -= 1
            text = calendar.expected_output_quarter(single_release_schedule(stamp, release), stamp, coverage)
            self.assertIn("2026q3 (no new quarter expected, subject to source availability)", text)

    def test_expected_quarter_handles_year_boundary_and_does_not_reduce_observed_coverage(self):
        stamp = datetime(2027, 1, 8, 8, 30, tzinfo=EASTERN)
        schedule = single_release_schedule(stamp)
        coverage = dict.fromkeys(RELEASES, 2026 * 4 + 3)
        coverage["Employment Situation"] -= 1
        text = calendar.expected_output_quarter(schedule, stamp, coverage)
        self.assertIn("2026q4 (subject to source availability)", text)
        coverage = dict.fromkeys(RELEASES, 2027 * 4)
        text = calendar.expected_output_quarter(schedule, stamp, coverage)
        self.assertIn("2027q1 (no new quarter expected, subject to source availability)", text)

    def test_input_coverage_uses_quarterly_rows_and_both_income_series(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "data_outputs").mkdir()
            (root / "data_raw").mkdir()
            for file in ("bls_pay", "bls_hours", "prices"):
                (root / f"data_outputs/{file}.csv").write_text(
                    "year,quarter,frequency\n2099,NA,annual\n2026,1,quarterly\n2026,3,quarterly\n"
                )
            bea = root / "data_raw/bea_api_output.csv"
            bea.write_text(
                "name,year,quarter,frequency\n"
                "nipa_ndp,2026,4,quarterly\nnipa_comp,2026,3,quarterly\n"
                "nipa_wage,2026,2,quarterly\nother_series,2099,1,quarterly\n"
            )
            coverage = calendar.read_input_coverage(root)
            self.assertEqual(coverage["Employment Situation"], 2026 * 4 + 2)
            self.assertEqual(coverage["Productivity and Costs"], 2026 * 4 + 2)
            self.assertEqual(coverage["Consumer Price Index"], 2026 * 4 + 2)
            self.assertEqual(coverage["Gross Domestic Product"], 2026 * 4 + 3)
            self.assertEqual(coverage["Personal Income and Outlays"], 2026 * 4 + 1)

    def test_coverage_cli_keeps_schedule_when_coverage_is_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            schedule = Path(directory) / "schedule.json"
            schedule.write_text(json.dumps(saved_schedule(datetime(2099, 1, 1, 8, 30, tzinfo=EASTERN))))
            command = [sys.executable, str(SCRIPT), "next", str(schedule), "--with-coverage"]
            result = subprocess.run(command, cwd=directory, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertIn("January 1, 2099, 2:27 PM EST", result.stdout)
            self.assertTrue(result.stdout.endswith("\n\n" + calendar.COVERAGE_UNAVAILABLE + "\n"))
            schedule.write_text("{}")
            result = subprocess.run(command, cwd=directory, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, calendar.UNAVAILABLE + "\n\n" + calendar.COVERAGE_UNAVAILABLE + "\n")

    def test_next_build_uses_daily_slot_then_unconditional_follow_up(self):
        stamp = datetime(2026, 11, 6, 8, 30, tzinfo=EASTERN)
        schedule = single_release_schedule(stamp)
        slot = stamp.replace(hour=14, minute=27)
        self.assertEqual(calendar.next_update(schedule, stamp),
                         "**Next scheduled update:** November 6, 2026, 2:27 PM EST, Employment Situation release.")
        for now in (slot, slot + timedelta(minutes=30)):
            self.assertEqual(calendar.next_update(schedule, now),
                             "**Next scheduled update:** November 7, 2026, 2:27 PM EST, next-day follow-up for Employment Situation.")

    def test_next_build_combines_and_deduplicates_overlapping_reasons(self):
        stamp = datetime(2026, 11, 5, 8, 30, tzinfo=EASTERN)
        schedule = single_release_schedule(stamp, "Productivity and Costs")
        event = {"source": "bls", "release": "Employment Situation", "at": (stamp + timedelta(days=1)).isoformat()}
        schedule["events"].extend([event, event])
        now = stamp.replace(hour=15)
        self.assertEqual(calendar.next_update(schedule, now),
                         "**Next scheduled update:** November 6, 2026, 2:27 PM EST, Employment Situation release and next-day follow-up for Productivity and Costs.")
        schedule["events"].append({**event, "release": "Consumer Price Index"})
        text = calendar.next_update(schedule, now)
        self.assertIn("Consumer Price Index release, Employment Situation release, and next-day follow-up for Productivity and Costs", text)
        self.assertNotIn(";", text)

    def test_next_build_time_follows_eastern_dst_and_calendar_boundaries(self):
        for stamp, date, zone in [
            (datetime(2026, 10, 31, 8, 30, tzinfo=EASTERN), "November 1, 2026", "EST"),
            (datetime(2026, 3, 7, 8, 30, tzinfo=EASTERN), "March 8, 2026", "EDT"),
            (datetime(2026, 12, 31, 8, 30, tzinfo=EASTERN), "January 1, 2027", "EST"),
        ]:
            with self.subTest(stamp=stamp):
                schedule = single_release_schedule(stamp)
                # At UTC midnight it is still the release date in Eastern time.
                now = (stamp + timedelta(days=1)).replace(hour=0, minute=0, tzinfo=timezone.utc)
                text = calendar.next_update(schedule, now)
                self.assertIn(f"{date}, 2:27 PM {zone}", text)
                self.assertIn("next-day follow-up", text)

    def test_release_after_daily_slot_only_gets_follow_up(self):
        stamp = datetime(2026, 11, 6, 16, 0, tzinfo=EASTERN)
        schedule = single_release_schedule(stamp)
        text = calendar.next_update(schedule, stamp.replace(hour=10))
        self.assertIn("November 7, 2026, 2:27 PM EST", text)
        self.assertIn("next-day follow-up for Employment Situation", text)
        self.assertFalse(calendar.due(schedule, stamp.replace(hour=14, minute=27)))

    def test_forecast_does_not_promise_a_build_that_calendar_gate_would_reject(self):
        stamp = datetime(2026, 11, 6, 8, 30, tzinfo=EASTERN)
        schedule = saved_schedule(stamp, future=False)
        schedule["events"].append({
            "source": "bls", "release": "Employment Situation", "at": "2026-11-09T13:30:00Z",
        })
        with self.assertRaises(ValueError):
            calendar.next_update(schedule, stamp + timedelta(days=1, hours=7))

    def test_last_follow_up_has_no_more_scheduled_builds(self):
        stamp = datetime(2026, 12, 31, 8, 30, tzinfo=EASTERN)
        schedule = saved_schedule(stamp, future=False)
        self.assertEqual(calendar.next_update(schedule, stamp + timedelta(days=1, hours=7)), calendar.UNAVAILABLE)
        self.assertEqual(calendar.expected_output_quarter(schedule, stamp + timedelta(days=1, hours=7)), calendar.COVERAGE_UNAVAILABLE)

    def test_forecast_daily_time_matches_scheduler_workflow(self):
        workflow = SCRIPT.parents[1] / "workflows/scheduled-data-update.yml"
        text = workflow.read_text()
        minute, hour = re.search(r'cron:\s*"(\d+) (\d+) \* \* \*"', text).groups()
        self.assertEqual((calendar.BUILD_TIME.hour, calendar.BUILD_TIME.minute), (int(hour), int(minute)))
        self.assertIn("timezone: America/New_York", text)

    def test_next_cli_falls_back_without_blocking_manual_refresh(self):
        with tempfile.TemporaryDirectory() as directory:
            schedule = Path(directory) / "schedule.json"
            for contents in (None, "{", "{}", json.dumps(saved_schedule(NOW - timedelta(days=10), future=False))):
                if contents is not None:
                    schedule.write_text(contents)
                result = subprocess.run([sys.executable, str(SCRIPT), "next", str(schedule)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout.strip(), calendar.UNAVAILABLE)
            result = subprocess.run([sys.executable, str(SCRIPT), "next"], cwd=directory, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.strip(), calendar.UNAVAILABLE)

    def test_agency_formats_select_all_five_releases_and_remove_duplicates(self):
        schedule = calendar.build_schedule(BLS, BEA, NOW)
        self.assertEqual(calendar.RELEASES, RELEASES)
        self.assertEqual({event["release"] for event in schedule["events"]}, set(RELEASES))
        self.assertEqual(len(schedule["events"]), 8)
        cpi = [event["at"] for event in schedule["events"] if event["release"] == "Consumer Price Index"]
        self.assertEqual(cpi, ["2026-11-10T13:30:00+00:00"])
        productivity = [event["at"] for event in schedule["events"] if event["release"] == "Productivity and Costs"]
        self.assertEqual(productivity, ["2026-11-05T13:30:00+00:00", "2026-12-08T13:30:00+00:00"])
        self.assertFalse(calendar.due(schedule, NOW))

    def test_bls_timezone_formats_preserve_the_release_instant(self):
        for zone, stamp, expected in [
            ("US-Eastern", "20260710T083000", "2026-07-10T12:30:00+00:00"),
            ("America/New_York", "20261210T083000", "2026-12-10T13:30:00+00:00"),
        ]:
            with self.subTest(zone=zone):
                text = "BEGIN:VCALENDAR\n" + bls_event("Consumer Price Index", stamp, timezone_name=zone) + "END:VCALENDAR\n"
                self.assertEqual(calendar.bls_events(text)[0][2].isoformat(), expected)
                utc_text = text.replace(f"DTSTART;TZID={zone}:{stamp}", "DTSTART:20261110T133000Z")
                self.assertEqual(calendar.bls_events(utc_text)[0][2].isoformat(), "2026-11-10T13:30:00+00:00")

    def test_release_time_follow_up_and_no_further_retry(self):
        stamp = datetime(2026, 10, 29, 8, 30, tzinfo=EASTERN)
        schedule = saved_schedule(stamp)
        self.assertFalse(calendar.due(schedule, stamp - timedelta(minutes=1)))
        self.assertTrue(calendar.due(schedule, stamp))
        self.assertTrue(calendar.due(schedule, stamp.replace(hour=14, minute=27)))
        self.assertTrue(calendar.due(schedule, stamp + timedelta(days=1)))
        self.assertFalse(calendar.due(schedule, stamp + timedelta(days=2)))

    def test_follow_up_uses_calendar_days_across_month_year_dst_and_weekend(self):
        for stamp in [
            datetime(2026, 10, 31, 8, 30, tzinfo=EASTERN),
            datetime(2026, 12, 31, 8, 30, tzinfo=EASTERN),
            datetime(2026, 3, 7, 8, 30, tzinfo=EASTERN),
            datetime(2026, 10, 30, 8, 30, tzinfo=EASTERN),
        ]:
            with self.subTest(release=stamp):
                schedule = saved_schedule(stamp)
                following_day = stamp + timedelta(days=1)
                self.assertTrue(calendar.due(schedule, following_day.replace(hour=14, minute=27)))
                self.assertFalse(calendar.due(schedule, stamp + timedelta(days=2)))

    def test_utc_midnight_still_uses_eastern_date(self):
        stamp = datetime(2026, 10, 29, 8, 30, tzinfo=EASTERN)
        schedule = saved_schedule(stamp)
        self.assertTrue(calendar.due(schedule, datetime(2026, 10, 31, 0, 27, tzinfo=timezone.utc)))
        self.assertFalse(calendar.due(schedule, datetime(2026, 10, 31, 4, 27, tzinfo=timezone.utc)))

    def test_overlapping_releases_and_follow_ups_make_one_boolean_decision(self):
        stamp = datetime(2026, 11, 5, 8, 30, tzinfo=EASTERN)
        schedule = saved_schedule(stamp)
        schedule["events"].append({
            "source": "bls", "release": "Employment Situation",
            "at": (stamp + timedelta(days=1)).isoformat(),
        })
        self.assertIs(calendar.due(schedule, stamp + timedelta(days=1, hours=6)), True)

    def test_calendar_refresh_retains_yesterday_for_follow_up(self):
        now = datetime(2026, 11, 6, 5, 17, tzinfo=EASTERN)
        schedule = calendar.build_schedule(BLS, BEA, now)
        self.assertIn("2026-11-05T13:30:00+00:00", [event["at"] for event in schedule["events"]])
        self.assertNotIn("2026-10-26T12:30:00+00:00", [event["at"] for event in schedule["events"]])
        self.assertTrue(calendar.due(schedule, now))

    def test_last_known_release_allows_its_follow_up_before_exhaustion(self):
        stamp = datetime(2026, 12, 31, 8, 30, tzinfo=EASTERN)
        schedule = saved_schedule(stamp, future=False)
        self.assertTrue(calendar.due(schedule, stamp + timedelta(days=1)))
        with self.assertRaises(ValueError):
            calendar.due(schedule, stamp + timedelta(days=2))

    def test_invalid_or_missing_required_release_fails(self):
        schedule = saved_schedule(NOW)
        schedule["events"] = [event for event in schedule["events"] if event["release"] != "Employment Situation"]
        with self.assertRaises(ValueError):
            calendar.due(schedule, NOW)
        schedule = saved_schedule(NOW)
        schedule["events"][0]["source"] = "unknown"
        with self.assertRaises(ValueError):
            calendar.due(schedule, NOW)
        with self.assertRaises((KeyError, ValueError)):
            calendar.build_schedule(BLS, "{}", NOW)
        with self.assertRaises(ValueError):
            calendar.build_schedule(BLS.replace("END:VCALENDAR", ""), BEA, NOW)
        for stamp in ("invalid", "2026-10-29T08:30:00"):
            with self.subTest(stamp=stamp), self.assertRaises(ValueError):
                calendar.parse_timestamp(stamp)

    def test_failed_download_or_invalid_feed_preserves_saved_file(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "schedule.json"
            output.write_text("previous schedule\n")
            for responses in ([OSError("BLS offline")], [BLS, OSError("BEA offline")], [BLS, "{}"]):
                with self.subTest(responses=responses[-1]), patch.object(calendar, "download", side_effect=responses):
                    with self.assertRaises((OSError, KeyError, ValueError)):
                        calendar.refresh(output, NOW)
                    self.assertEqual(output.read_text(), "previous schedule\n")

    def test_successful_refresh_writes_the_validated_schedule(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "schedule.json"
            with patch.object(calendar, "download", side_effect=[BLS, BEA]):
                calendar.refresh(output, NOW)
            self.assertEqual(json.loads(output.read_text()), calendar.build_schedule(BLS, BEA, NOW))

    def test_bls_download_requires_contact_and_handles_byte_order_mark(self):
        with patch.dict(os.environ, {"BLS_DOWNLOAD_EMAIL": ""}), patch.object(calendar, "urlopen") as fetch:
            with self.assertRaises(ValueError):
                calendar.download(calendar.BLS_URL)
            fetch.assert_not_called()
        with patch.dict(os.environ, {"BLS_DOWNLOAD_EMAIL": "fixture@example.invalid"}), patch.object(calendar, "urlopen") as fetch:
            fetch.return_value.__enter__.return_value.read.return_value = b"\xef\xbb\xbfBEGIN:VCALENDAR"
            self.assertEqual(calendar.download(calendar.BLS_URL), "BEGIN:VCALENDAR")
            self.assertIn("fixture@example.invalid", fetch.call_args.args[0].get_header("User-agent"))

    def test_due_cli_fails_for_missing_or_malformed_saved_calendar(self):
        with tempfile.TemporaryDirectory() as directory:
            schedule = Path(directory) / "schedule.json"
            for contents in (None, "{", "{}"):
                if contents is not None:
                    schedule.write_text(contents)
                result = subprocess.run([sys.executable, str(SCRIPT), "due", str(schedule)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
