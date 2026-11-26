import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest


SCRIPT = Path(__file__).with_name("summarize.py")


def row(**changes):
    return {
        "schema": 1,
        "run_id": "synthetic-run",
        "attempt": 1,
        "platform": "iphone-simulator",
        "os_build": "24A123",
        "build": "abc123",
        "route": "lab_ax",
        "app": "lab.ax-fixture",
        "control": "plain_button",
        "op": "activate",
        "scenario": "warm_asserted_other_app_front",
        "case_id": "uikit-warm-activate",
        "outcome": "verified",
        "delivery": "sent",
        "verification": "expected_effect",
        "foreground": {
            "expected": "sentinel",
            "telemetry": "sampled",
            "observed_switches": 0,
            "unexpected_input": False,
        },
        "error": None,
        "ms": {"total": 20},
        **changes,
    }


def jsonl(*rows):
    return "".join(json.dumps(entry) + "\n" for entry in rows)


class SummarizeTests(unittest.TestCase):
    def run_cli(self, data="", *paths):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, paths)],
            input=data.encode("utf-8") if isinstance(data, str) else data,
            capture_output=True,
        )

    def render(self, *rows):
        result = self.run_cli(jsonl(*rows))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout.decode()

    def test_counts_timings_and_partial_foreground_evidence(self):
        report = self.render(
            row(ms={"total": 10, "attach": None, "verify": 3}),
            row(
                attempt=2, outcome="unsupported", verification="no_expected_effect",
                foreground=dict(row()["foreground"], observed_switches=2, unexpected_input=True),
                error={"reason": "requires_visible_touch", "message": "never print this"},
                ms={"total": 40, "attach": 1.5, "verify": None},
            ),
            row(
                attempt=3, outcome="timeout", delivery="unknown", verification="callback_only",
                foreground=dict(row()["foreground"], telemetry="incomplete",
                                observed_switches=1, unexpected_input=None),
                error={"reason": "effect_unverified"},
                ms={"total": None, "attach": None},
            ),
            row(
                attempt=4, outcome="not_applicable", delivery=None, verification=None,
                foreground=None, ms={"total": None},
            ),
        )
        self.assertIn("Attempts: 4", report)
        self.assertIn(
            r"| 4 | 1/4 | 2/4 | not\_applicable: 1, timeout: 1, unsupported: 1, verified: 1 |",
            report,
        )
        self.assertIn("sent: 2, unknown: 1, (unmeasured): 1", report)
        self.assertIn(r"callback\_only: 1, expected\_effect: 1, no\_expected\_effect: 1, (unmeasured): 1", report)
        self.assertIn(r"| effect\_unverified: 1, requires\_visible\_touch: 1 |", report)
        self.assertIn("| 1 | total | 2/4 | 10 | 40 |", report)
        self.assertIn("| 1 | attach | 1/4 | 1.5 | 1.5 |", report)
        self.assertIn("| 1 | verify | 1/4 | 3 | 3 |", report)
        self.assertIn(
            "| 1 | sentinel: 3, (unmeasured): 1 | incomplete: 1, sampled: 2, (unmeasured): 1 "
            "| 3/4 | 3 | 2 | 2/4 | 1 |",
            report,
        )
        self.assertNotIn("never print this", report)
        self.assertNotIn("synthetic-run", report)

    def test_nearest_rank_and_order_independence(self):
        rows = [
            row(attempt=n, ms={"total": n, "dispatch": 1 if n % 2 else 1.0})
            for n in range(1, 21)
        ]
        report = self.render(*rows)
        self.assertIn("| 1 | total | 20/20 | 10 | 19 |", report)
        self.assertEqual(report, self.render(*reversed(rows)))

    def test_group_dimensions_and_attempt_identity(self):
        report = self.render(
            row(), row(run_id="different-run"), row(attempt=2),
            row(build="def456"), row(os_build="24A456"), row(platform="other-simulator"),
            row(route="xctest"), row(app="lab.other"), row(control="switch"),
            row(op="look"), row(scenario="cold"), row(case_id="other-case"),
        )
        self.assertEqual(report.count("\n## "), 4)
        self.assertIn("## iphone-simulator / OS 24A123 / build abc123", report)
        self.assertIn("## iphone-simulator / OS 24A123 / build def456", report)
        self.assertIn("## iphone-simulator / OS 24A456 / build abc123", report)
        self.assertIn("## other-simulator / OS 24A123 / build abc123", report)
        self.assertIn("| uikit-warm-activate | 3 | 3/3 | 3/3 |", report)
        self.assertEqual(report.count("| 1 | 1/1 | 1/1 | verified: 1 |"), 9)

    def test_missing_measurements_are_not_zero(self):
        report = self.render(row(
            outcome="not_applicable", delivery="not_sent", verification="not_applicable",
            foreground={"expected": "sentinel", "telemetry": "not_measured",
                        "observed_switches": None, "unexpected_input": None},
            ms={"total": None, "dispatch": None},
        ))
        self.assertIn("| 1 | total | 0/1 | — | — |", report)
        self.assertIn("| 1 | dispatch | 0/1 | — | — |", report)
        self.assertIn(r"| 1 | sentinel: 1 | not\_measured: 1 | 0/1 | — | — | 0/1 | — |", report)

    def test_duplicate_attempt_across_files_stops_without_partial_report(self):
        with TemporaryDirectory() as directory:
            first = Path(directory) / "first.jsonl"
            second = Path(directory) / "second.jsonl"
            first.write_text(jsonl(row()), encoding="utf-8")
            second.write_text(jsonl(row(attempt=2), row(outcome="blocked")), encoding="utf-8")
            result = self.run_cli("", first, second)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b"")
        self.assertIn(f"{second}:2: duplicate attempt (first seen at {first}:1)", result.stderr.decode())

    def test_malformed_rows_point_to_line_and_emit_no_report(self):
        cases = (
            (b"{bad}\n", "Expecting property name"),
            (b"\n", "Expecting value"),
            (b"\xff\n", "invalid UTF-8"),
            (b"[]\n", "row must be an object"),
            (b'{"schema":1,"schema":1}\n', "duplicate JSON object key"),
            (jsonl(row(schema=True)), "schema must be the integer 1"),
            (jsonl(row(schema=2)), "schema must be the integer 1"),
            (jsonl(row(case_id=None)), "case_id must be"),
            (jsonl(row(attempt=0)), "attempt must be"),
            (jsonl(row(attempt=1.0)), "attempt must be"),
            (jsonl(row(outcome="ignored")), "unknown outcome"),
            (jsonl(row(delivery="delivered")), "unknown delivery"),
            (jsonl(row(error={"reason": []})), "error.reason must be"),
            (jsonl(row(foreground={"observed_switches": True})), "foreground.observed_switches must be"),
            (jsonl(row(foreground={"unexpected_input": 0})), "foreground.unexpected_input must be"),
            (jsonl(row(ms={})), "missing ms.total"),
            (jsonl(row(ms={"total": -1})), "ms timings must be"),
            (jsonl(row(ms={"total": True})), "ms timings must be"),
            (jsonl(row(ms={"total": float("nan")})), "non-finite JSON number"),
        )
        for data, message in cases:
            with self.subTest(message=message):
                encoded = data.encode("utf-8") if isinstance(data, str) else data
                result = self.run_cli(jsonl(row()).encode("utf-8") + encoded)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
                self.assertIn("<stdin>:2", result.stderr.decode())
                self.assertIn(message, result.stderr.decode())

    def test_empty_input_and_markdown_escaping(self):
        self.assertEqual(self.render(), "# Background matrix summary\n\nAttempts: 0\n")
        report = self.render(row(app="<fixture>|code", case_id="[case](https://example.invalid)"))
        self.assertIn(r"| &lt;fixture&gt;\|code |", report)
        self.assertIn(r"\[case\](https://example.invalid)", report)


if __name__ == "__main__":
    unittest.main()
