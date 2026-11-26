"""Summarize schema-1 matrix JSONL without inferring missing observations."""

import argparse
from collections import Counter, defaultdict
from contextlib import nullcontext
from decimal import Decimal, InvalidOperation
from html import escape
import json
import sys


ENVIRONMENT = ("platform", "os_build", "build")
CELL = ("route", "app", "control", "op", "scenario", "case_id")
OUTCOMES = {
    "verified", "unsupported", "blocked", "not_applicable", "timeout",
    "unverified", "safety_abort",
}


def check_text(value, field, *, nullable=False):
    if nullable and value is None:
        return
    if not isinstance(value, str) or not value.strip() or not value.isprintable():
        raise ValueError(f"{field} must be a nonblank, printable string")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON object key")
        result[key] = value
    return result


def reject_constant(_):
    raise ValueError("non-finite JSON number")


def parse_row(line):
    row = json.loads(
        line.decode("utf-8"), object_pairs_hook=unique_object,
        parse_float=Decimal, parse_constant=reject_constant,
    )
    if not isinstance(row, dict):
        raise ValueError("row must be an object")
    if type(row.get("schema")) is not int or row["schema"] != 1:
        raise ValueError("schema must be the integer 1")
    for field in ("run_id", *ENVIRONMENT, *CELL):
        check_text(row.get(field), field)
    if type(row.get("attempt")) is not int or row["attempt"] < 1:
        raise ValueError("attempt must be a positive integer")

    for field in ("outcome", "delivery", "verification"):
        if field not in row:
            raise ValueError(f"missing {field}")
        check_text(row[field], field, nullable=field != "outcome")
    if row["outcome"] not in OUTCOMES:
        raise ValueError("unknown outcome")
    if row["delivery"] not in (None, "not_sent", "sent", "unknown"):
        raise ValueError("unknown delivery")

    if "foreground" not in row:
        raise ValueError("missing foreground")
    foreground = row["foreground"]
    if foreground is not None:
        if not isinstance(foreground, dict):
            raise ValueError("foreground must be an object or null")
        for field in ("expected", "telemetry"):
            check_text(foreground.get(field), f"foreground.{field}", nullable=True)
        switches = foreground.get("observed_switches")
        if switches is not None and (type(switches) is not int or switches < 0):
            raise ValueError("foreground.observed_switches must be a nonnegative integer or null")
        unexpected = foreground.get("unexpected_input")
        if unexpected is not None and type(unexpected) is not bool:
            raise ValueError("foreground.unexpected_input must be a boolean or null")

    error = row.get("error")
    if error is not None:
        if not isinstance(error, dict):
            raise ValueError("error must be an object or null")
        check_text(error.get("reason"), "error.reason", nullable=True)

    timings = row.get("ms")
    if not isinstance(timings, dict):
        raise ValueError("ms must be an object")
    if "total" not in timings:
        raise ValueError("missing ms.total")
    for stage, duration in timings.items():
        check_text(stage, "ms stage name")
        if duration is not None and (
            type(duration) not in (int, Decimal)
            or (isinstance(duration, Decimal) and not duration.is_finite())
            or duration < 0
        ):
            raise ValueError("ms timings must be nonnegative numbers or null")
    return row


def load(paths):
    groups = defaultdict(lambda: defaultdict(list))
    seen = {}
    for path in paths:
        source = "<stdin>" if path == "-" else path
        with (nullcontext(sys.stdin.buffer) if path == "-" else open(path, "rb")) as stream:
            for number, line in enumerate(stream, 1):
                location = f"{source}:{number}"
                try:
                    row = parse_row(line)
                except json.JSONDecodeError as exc:
                    raise ValueError(f"{location}:{exc.colno}: {exc.msg}") from None
                except UnicodeDecodeError:
                    raise ValueError(f"{location}: invalid UTF-8") from None
                except (InvalidOperation, RecursionError):
                    raise ValueError(f"{location}: JSON number or nesting out of range") from None
                except ValueError as exc:
                    raise ValueError(f"{location}: {exc}") from None
                environment = tuple(row[field] for field in ENVIRONMENT)
                cell = tuple(row[field] for field in CELL)
                key = (environment, cell, row["run_id"], row["attempt"])
                if key in seen:
                    raise ValueError(f"{location}: duplicate attempt (first seen at {seen[key]})")
                seen[key] = location
                groups[environment][cell].append(row)
    return groups


def markdown(value):
    result = escape(str(value), quote=False)
    for character in ("\\", "|", "`", "*", "_", "[", "]", "~", "#", "!"):
        result = result.replace(character, "\\" + character)
    return result


def table(headers, rows):
    def line(cells):
        return "| " + " | ".join(map(markdown, cells)) + " |"

    yield line(headers)
    yield line(["---"] * len(headers))
    yield from map(line, rows)


def counts(values):
    tally = Counter(values)
    return ", ".join(
        f"{label if label is not None else '(unmeasured)'}: {tally[label]}"
        for label in sorted(tally, key=lambda label: (label is None, label))
    ) or "—"


def summarize(groups):
    total = sum(len(rows) for cells in groups.values() for rows in cells.values())
    yield "# Background matrix summary"
    yield ""
    yield f"Attempts: {total}"
    if not total:
        return
    yield ""
    yield "Timings are in milliseconds; p50 and p95 use nearest rank over non-null samples."
    yield "Witnessed attempts have sampled telemetry and both switch and sentinel observations."
    yield "Sampling does not establish continuous monitoring."
    yield "Switches are observed transitions, not attributed to the tool; sentinel counts are attempts reporting unexpected input."

    for (platform, os_build, build), cells in sorted(groups.items()):
        yield ""
        yield f"## {markdown(platform)} / OS {markdown(os_build)} / build {markdown(build)}"
        outcomes, timings, witnesses = [], [], []
        for cell_number, (cell, rows) in enumerate(sorted(cells.items()), 1):
            size = len(rows)
            foreground = [row["foreground"] or {} for row in rows]
            witnessed = sum(
                entry.get("telemetry") == "sampled"
                and entry.get("observed_switches") is not None
                and entry.get("unexpected_input") is not None
                for entry in foreground
            )
            outcomes.append((
                cell_number, *cell, size,
                f"{sum(row['outcome'] == 'verified' for row in rows)}/{size}",
                f"{witnessed}/{size}",
                counts(row["outcome"] for row in rows),
                counts(row["delivery"] for row in rows),
                counts(row["verification"] for row in rows),
                counts(row["error"]["reason"] for row in rows if (row.get("error") or {}).get("reason") is not None),
            ))
            stages = {stage for row in rows for stage in row["ms"]}
            for stage in ("total", *sorted(stages - {"total"})):
                samples = sorted(
                    (duration for row in rows if (duration := row["ms"].get(stage)) is not None),
                    key=lambda duration: (duration, str(duration)),
                )
                n = len(samples)
                timings.append((
                    cell_number, stage, f"{n}/{size}",
                    *(samples[(n * p + 99) // 100 - 1] if n else "—" for p in (50, 95)),
                ))

            switches = [entry["observed_switches"] for entry in foreground if entry.get("observed_switches") is not None]
            inputs = [entry["unexpected_input"] for entry in foreground if entry.get("unexpected_input") is not None]
            witnesses.append((
                cell_number,
                counts(entry.get("expected") for entry in foreground),
                counts(entry.get("telemetry") for entry in foreground),
                f"{len(switches)}/{size}",
                sum(switches) if switches else "—",
                sum(value > 0 for value in switches) if switches else "—",
                f"{len(inputs)}/{size}",
                sum(inputs) if inputs else "—",
            ))

        yield ""
        yield from table(
            ("Cell", "Route", "App", "Control", "Operation", "Scenario", "Case", "Attempts",
             "Verified", "Witnessed", "Outcomes", "Delivery", "Verification", "Error reasons"),
            outcomes,
        )
        yield ""
        yield from table(("Cell", "Stage", "Measured", "p50", "p95"), timings)
        yield ""
        yield from table(
            ("Cell", "Expected foreground", "Telemetry", "Switch coverage", "Switches",
             "Attempts with switches", "Sentinel coverage", "Attempts with unexpected input"),
            witnesses,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="JSONL paths; use - for stdin (the default)")
    args = parser.parse_args()
    try:
        groups = load(args.paths or ["-"])
    except (OSError, ValueError) as exc:
        parser.exit(1, f"{parser.prog}: {exc}\n")
    print("\n".join(summarize(groups)))


if __name__ == "__main__":
    main()
