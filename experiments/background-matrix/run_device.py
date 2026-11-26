import argparse
import datetime
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time


LAB = "nz.zheha.poki.lab"
FIXTURE = "local.pokimcp.axfixture"
SENTINEL = "local.pokimcp.matrixsentinel"
CASES = ("uikit-read", "uikit-bar", "uikit-set", "uikit-plain")
CONTAINER = ("--domain-type", "appDataContainer", "--domain-identifier", LAB)


def call(*args, limit=12):
    return subprocess.run(args, capture_output=True, timeout=limit)


def dev(*args, limit=8, required=True):
    result = call("xcrun", "devicectl", *args, limit=limit)
    if required and result.returncode:
        raise RuntimeError(f"CoreDevice failed during {' '.join(args[:3])}")
    return result


def query(*args):
    result = dev(*args, "--json-output", "-")
    return json.loads(result.stdout)["result"]


def preflight(app, bundle, udid):
    plist = plistlib.loads((app / "Info.plist").read_bytes())
    if plist.get("CFBundleIdentifier") != bundle or plist.get("UIDeviceFamily") != [1]:
        raise RuntimeError(f"Unexpected bundle or device family for {bundle}")
    if call("codesign", "--verify", "--strict", "--deep", str(app)).returncode:
        raise RuntimeError(f"Signature verification failed for {bundle}")
    embedded = call("security", "cms", "-D", "-i", str(app / "embedded.mobileprovision"))
    if embedded.returncode:
        raise RuntimeError(f"No embedded development profile for {bundle}")
    profile = plistlib.loads(embedded.stdout)
    signed = call("codesign", "-d", "--xml", "--entitlements", "-", str(app))
    if signed.returncode or not signed.stdout:
        raise RuntimeError(f"No signed entitlements for {bundle}")
    entitlements = plistlib.loads(signed.stdout)
    grants = profile["Entitlements"]
    expiry = profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc)
    app_id = entitlements.get("application-identifier", "")
    grant = grants.get("application-identifier", "")
    if not app_id.endswith(f".{bundle}") or not (grant == app_id or
            (grant.endswith(".*") and app_id.startswith(grant[:-1]))):
        raise RuntimeError(f"Profile does not authorize the signed identity of {bundle}")
    if expiry <= datetime.datetime.now(datetime.timezone.utc) or not all(
        values.get("get-task-allow") for values in (entitlements, grants)
    ) or udid.lower() not in {d.lower() for d in profile.get("ProvisionedDevices", [])}:
        raise RuntimeError(f"Profile does not authorize development on this iPhone for {bundle}")
    allowed = {"application-identifier", "com.apple.developer.team-identifier", "get-task-allow",
               "keychain-access-groups"}
    if set(entitlements) - allowed:
        raise RuntimeError(f"Unexpected signed entitlements for {bundle}")


def run(args, output):
    deadline = time.monotonic() + 240
    devices = query("list", "devices")["devices"]
    matches = [
        d for d in devices
        if args.device in (d.get("identifier"), d["hardwareProperties"].get("udid"))
        and d["hardwareProperties"].get("productType") == "iPhone18,1"
        and d["connectionProperties"].get("transportType") == "wired"
        and d["deviceProperties"].get("developerModeStatus") == "enabled"
        and d["deviceProperties"].get("osBuildUpdate") == "24C5037i"
    ]
    if len(matches) != 1:
        raise RuntimeError("No unique approved wired iPhone 17 Pro on build 24C5037i with Developer Mode on")
    device = ("--device", matches[0]["identifier"])
    udid = matches[0]["hardwareProperties"]["udid"]
    lock = query("device", "info", "lockState", *device)
    if lock.get("passcodeRequired") is not False or lock.get("unlockedSinceBoot") is not True:
        raise RuntimeError("The iPhone currently requires an unlock; stopped without asking for input")
    products = ((LAB, args.lab), (FIXTURE, args.fixture), (SENTINEL, args.sentinel))
    for bundle, app in products:
        preflight(app, bundle, udid)
    if list((args.lab / "PlugIns").glob("*.appex")):
        raise RuntimeError("Refusing a Lab build with an embedded extension")
    for bundle, _ in products:
        if query("device", "info", "apps", *device, "--include-all-apps", "--bundle-id", bundle)["apps"]:
            raise RuntimeError(f"Refusing to overwrite an existing install of {bundle}")

    def check_budget():
        if time.monotonic() >= deadline:
            raise RuntimeError("Four-minute run deadline reached; reserved remaining time for cleanup")

    def launch(bundle, *arguments, fresh=False):
        check_budget()
        dev("device", "process", "launch", *device, "--timeout", "5",
            *(("--terminate-existing",) if fresh else ()), "--", bundle, *arguments)

    def fetch(lane, name, path):
        source = f"Documents/BackgroundMatrix/{lane}/{name}"
        path.unlink(missing_ok=True)
        return dev("device", "copy", "from", *device, *CONTAINER, "--timeout", "3",
                   "--source", source, "--destination", str(path), limit=5, required=False).returncode == 0

    installed = []
    active_lane = None
    with tempfile.TemporaryDirectory() as temp:
        scratch = Path(temp)
        stop_file = scratch / "stop"
        stop_file.touch()

        def stop(lane, required=True):
            return dev("device", "copy", "to", *device, *CONTAINER, "--timeout", "3",
                       "--source", str(stop_file), "--destination", f"Documents/BackgroundMatrix/{lane}/stop",
                       limit=5, required=required)

        try:
            for bundle, app in products:
                check_budget()
                installed.append(bundle)
                dev("device", "install", "app", *device, str(app), "--timeout", "15", limit=18)
            for lane in ("safety", "controls"):
                active_lane = lane
                launch(LAB, "-pokiDeviceMatrixAuto", "YES", "-pokiDeviceMatrixLane", lane,
                       "-pokiMatrixBuild", args.build, "-pokiMatrixOSBuild", "24C5037i", fresh=True)
                print(f"Started {lane}", flush=True)
                ready_deadline = time.monotonic() + 10
                ready = False
                staged = set()
                state_path = scratch / "phase"
                while True:
                    check_budget()
                    if not ready and time.monotonic() >= ready_deadline:
                        raise RuntimeError("Automation never became ready within 10 seconds; possible consent prompt")
                    if fetch(lane, "phase", state_path):
                        state = state_path.read_text()
                        if state == "done":
                            break
                        if state in ("cleanup_unconfirmed", "output_failed"):
                            raise RuntimeError(f"Lab stopped in {state}; do not retry")
                        if state == "awaiting_authorization":
                            raise RuntimeError("iOS Automation Mode is waiting for authorization; stopped without answering")
                        if state not in staged:
                            if lane == "safety" and state == "waiting_stop":
                                ready = True
                                stop(lane)
                            if lane == "controls" and state == "waiting_target":
                                ready = True
                                launch(FIXTURE, "-matrix-controls")
                            if lane == "controls" and state == "waiting_sentinel":
                                launch(SENTINEL)
                            staged.add(state)
                    time.sleep(0.25)
                active_lane = None
                rows_path = scratch / "rows"
                if not fetch(lane, "run.jsonl", rows_path):
                    raise RuntimeError("Lab cleanup finished but rows could not be exported")
                text = rows_path.read_text()
                rows = [json.loads(line) for line in text.splitlines()]
                expected = ("device-local-stop",) if lane == "safety" else CASES
                if tuple(r["case_id"] for r in rows) != expected or any(r["platform"] != "iphone" for r in rows):
                    raise RuntimeError("Lab returned unexpected rows")
                output.write(text)
                output.flush()
                if lane == "safety":
                    if (rows[0]["outcome"], rows[0]["delivery"]) != ("verified", "not_sent"):
                        raise RuntimeError("Local Stop did not pass its cleanup gate")
                    if rows[0]["watermark"] == "observed_in_system_ax":
                        raise RuntimeError("Watermark was seen, but there is no independent clearance witness")
        finally:
            if active_lane is not None:
                try:
                    stop(active_lane, required=False)
                except subprocess.TimeoutExpired:
                    pass
            for bundle in reversed(installed):
                try:
                    result = dev("device", "uninstall", "app", *device, bundle, "--timeout", "7",
                                 limit=9, required=False)
                    if result.returncode:
                        print(f"Uninstall was not confirmed for {bundle}", flush=True)
                    else:
                        print(f"Uninstalled {bundle}", flush=True)
                except subprocess.TimeoutExpired:
                    print(f"Uninstall timed out for {bundle}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True, help="Locally supplied CoreDevice UUID or hardware UDID")
    parser.add_argument("--lab", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--sentinel", type=Path, required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        with args.out.open("x") as output:
            run(args, output)
    except subprocess.TimeoutExpired:
        parser.exit(1, "Stopped after a CoreDevice or signature-check timeout. Do not retry on the phone.\n")
    except (RuntimeError, ValueError, OSError, KeyError) as error:
        parser.exit(1, f"Stopped: {error if isinstance(error, RuntimeError) else type(error).__name__}\n")


if __name__ == "__main__":
    main()
