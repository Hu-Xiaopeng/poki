# Poki Lab background compatibility matrix

This experiment compares specific accessibility operations on synthetic fixtures while a sentinel app stays visible. It does not expose a chat or MCP tool, read a user's apps, or fall back to foreground input. The ordinary Poki projects do not link the matrix. The Lab project uses `nz.zheha.poki.lab` and `group.nz.zheha.poki.lab`; its Swift and Objective-C flags are empty by default and can only enable this path for Debug on iPhone Simulator. Starting the probe additionally requires an explicit per-launch switch.

## Build and run on a dedicated iPhone simulator

Use Xcode 27.3, XcodeGen, Python 3 and the repo's usual launcher and asset build steps. Do not use a simulator belonging to another thread. Do not run this against a device or an iPad.

```sh
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
OUT="$(mktemp -d)"
SIM="$(xcrun simctl create 'Poki Lab Background Matrix' com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-3)"
xcrun simctl boot "$SIM"
native/launcher/fetch-idevice.sh
rustup target add aarch64-apple-ios-sim
cargo build --release --locked --target aarch64-apple-ios-sim --manifest-path native/launcher/Cargo.toml
native/ios-app/scripts/make-assets.sh
xcodegen generate --spec native/ios-app/project-lab.yml
xcodebuild build -project native/ios-app/PokiLab.xcodeproj -scheme Poki -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUT/lab" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO \
  POKI_MATRIX_SWIFT_FLAG=POKI_BACKGROUND_MATRIX POKI_MATRIX_NATIVE_FLAG=POKI_BACKGROUND_MATRIX=1
xcodegen generate --spec experiments/background-matrix/SimulatorSentinel/project.yml
xcodebuild build -project experiments/background-matrix/SimulatorSentinel/MatrixSentinel.xcodeproj \
  -scheme MatrixSentinel -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUT/sentinel" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
xcodebuild build -project experiments/background-ax-probe/BackgroundAXProbe.xcodeproj -target AXFixture \
  -configuration Debug -sdk iphonesimulator CONFIGURATION_BUILD_DIR="$OUT/fixture" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
xcrun simctl bootstatus "$SIM" -b
xcrun simctl install "$SIM" "$OUT/lab/Build/Products/Debug-iphonesimulator/Poki.app"
xcrun simctl install "$SIM" "$OUT/sentinel/Build/Products/Debug-iphonesimulator/MatrixSentinel.app"
xcrun simctl install "$SIM" "$OUT/fixture/AXFixture.app"
python3 experiments/background-matrix/run_simulator.py --simulator "$SIM" --build "$(git rev-parse HEAD)" \
  --attempts 5 --out "$OUT/ax.jsonl" controls level_two swiftui web unseen unasserted
python3 experiments/background-matrix/summarize.py "$OUT/ax.jsonl" > "$OUT/summary.md"
```

For the optional `flutter`, `compose`, and `react_native` suites, use unmodified fixture sources from the [snap-window experiment](https://github.com/JosssphZhou/poki/tree/523e13b265007dd3322500f17014829ce421b94b/experiments/background-ax-probe/toolkit-fixtures). Install only their simulator builds on the dedicated simulator, then pass their suite names to the same command with a fresh output file. React Native can run from a Release build with the JS bundle embedded, without Metro. Do not combine toolkit dependencies with the Poki Lab build.

Tests:

```sh
swift test --package-path experiments/background-matrix
python3 -B -m unittest discover -s experiments/background-matrix -p 'test_summarize.py' -v
```

## What the runner measures

Every trial starts a fresh Lab process. The host stages only the fixture and the sentinel, and never launches another app once the sentinel is visible. Before switching away, the adapter confirms the fixture's expected foreground AX marker; without a baseline, the measured lane is not applicable. The adapter binds a unique element from the current snapshot to the fixture bundle, PID, process start, and session generation. It refuses missing or stale identity; never sends coordinates, system keys, or a retry; and stops the trial on unknown delivery, cancellation, or unexpected foreground evidence. A fixture-only accessibility action may still be semantically unsupported. The back probe includes one layout audit, not a second action. No arbitrary numeric actions are accepted.

The sentinel counts observed touch/press starts. Foreground sampling is a point-in-time witness, not proof about gaps between samples, and it does not establish concurrent physical use. A dispatched reply is not success: the matrix checks the expected fixture field value, callback marker, scroll offset, or destination content. If only the transport responds and the effect isn't visible in accessibility, report it as unverified rather than success. No live screenshot is taken; the screenshot cell checks safe refusal.

JSONL uses the versioned manifest in `Sources/BackgroundMatrix/Matrix.swift` and schema version 1 in `Log.swift`. The adapter retains AX labels only in memory to verify synthetic expected properties; no snapshots, app inventory, process IDs, user-provided strings, or raw daemon errors go into the file. The host exports only the normalized JSONL rows. To stop a live simulator trial, create the `stop` file next to the Lab container's `Documents/BackgroundMatrix/phase`; the runner checks it before dispatch and during readback. The session closes after each trial. A dedicated lab device run is a separate approval and implementation step.
