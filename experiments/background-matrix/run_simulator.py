import argparse
import json
import os
from pathlib import Path
import subprocess
import time


LAB = "nz.zheha.poki.lab"
SENTINEL = "local.pokimcp.matrixsentinel"
AX_FIXTURE = "local.pokimcp.axfixture"
SUITES = {
    "controls": (AX_FIXTURE, "-matrix-controls"),
    "level_two": (AX_FIXTURE, "-matrix-level-two"),
    "swiftui": (AX_FIXTURE, "-coverage", "-matrix-swiftui"),
    "web": (AX_FIXTURE, "-coverage", "-matrix-web"),
    "unseen": (),
    "unasserted": (AX_FIXTURE, "-matrix-controls"),
    "flutter": ("local.pokimcp.flutterfix",),
    "compose": ("local.pokimcp.composefix",),
    "react_native": ("local.pokimcp.rnfix",),
}


def simctl(*args, env=None, check=True):
    return subprocess.run(
        ["xcrun", "simctl", *args], env=env, check=check, text=True, capture_output=True, timeout=30
    )


def run_one(udid, suite, attempt, build, os_build, env, path):
    fixture = SUITES[suite]
    for bundle in {LAB, SENTINEL, AX_FIXTURE} | ({fixture[0]} if fixture else set()):
        simctl("terminate", udid, bundle, check=False)
    for name in ("phase", "run.jsonl", "stop"):
        (path / name).unlink(missing_ok=True)
    simctl("launch", udid, LAB, "-pokiBackgroundMatrix", "YES", "-pokiMatrixSuite", suite,
           "-pokiMatrixAttempt", str(attempt), "-pokiMatrixBuild", build, "-pokiMatrixOSBuild", os_build, env=env)

    staged = set()
    deadline = time.monotonic() + 80
    try:
        while time.monotonic() < deadline:
            phase = path / "phase"
            state = phase.read_text() if phase.is_file() else ""
            if state == "done":
                output = (path / "run.jsonl").read_text()
                rows = [json.loads(line) for line in output.splitlines()]
                if not rows or any(row["attempt"] != attempt for row in rows):
                    raise RuntimeError("Run did not produce its expected attempt rows")
                return output
            if state == "output_failed":
                raise RuntimeError("Lab could not write the trial results")
            if state == "waiting_target" and state not in staged:
                simctl("launch", udid, *fixture)
                staged.add(state)
            if state == "waiting_sentinel" and state not in staged:
                simctl("launch", udid, SENTINEL)
                staged.add(state)
            time.sleep(0.10)
        raise RuntimeError("Timed out waiting for Lab to finish")
    finally:
        if (path / "phase").is_file() and (path / "phase").read_text() != "done":
            (path / "stop").touch()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--attempts", type=int, choices=range(1, 101), default=5)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("suites", nargs="*", default=list(SUITES))
    args = parser.parse_args()
    if not set(args.suites) <= SUITES.keys():
        parser.error("Unknown fixture suite")

    devices = json.loads(simctl("list", "devices", "booted", "-j").stdout)["devices"]
    runtimes = json.loads(simctl("list", "runtimes", "-j").stdout)["runtimes"]
    runtime = next((key for key, entries in devices.items() for entry in entries
                    if entry["udid"] == args.simulator and entry["name"].startswith("Poki")
                    and entry["name"].endswith("Background Matrix") and "iPhone" in entry["deviceTypeIdentifier"]), None)
    if runtime is None:
        parser.error("Select a dedicated, booted iPhone simulator named 'Poki … Background Matrix'")
    os_build = next(item["buildversion"] for item in runtimes if item["identifier"] == runtime)
    path = Path(simctl("get_app_container", args.simulator, LAB, "data").stdout.strip()) / "Documents" / "BackgroundMatrix"
    dev = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
    sdk_dev = Path(dev) / "Platforms" / "iPhoneSimulator.platform" / "Developer"
    env = os.environ | {
        "SIMCTL_CHILD_POKI_SIMULATOR_DEVELOPER_DIR": str(sdk_dev),
        "SIMCTL_CHILD_DYLD_FRAMEWORK_PATH": f"{sdk_dev}/Library/Frameworks:{sdk_dev}/Library/PrivateFrameworks",
        "SIMCTL_CHILD_DYLD_LIBRARY_PATH": str(sdk_dev / "usr" / "lib"),
    }
    with args.out.open("x") as output:
        for suite in args.suites:
            for attempt in range(1, args.attempts + 1):
                rows = run_one(args.simulator, suite, attempt, args.build, os_build, env, path)
                output.write(rows)
                output.flush()
                print(f"{suite} {attempt}/{args.attempts}: {len(rows.splitlines())} rows", flush=True)


if __name__ == "__main__":
    main()
