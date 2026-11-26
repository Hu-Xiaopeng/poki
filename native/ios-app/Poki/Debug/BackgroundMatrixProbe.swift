#if (POKI_BACKGROUND_MATRIX && targetEnvironment(simulator)) || (DEBUG && POKI_BACKGROUND_MATRIX_DEVICE)
import BackgroundMatrix
import Foundation
import UIKit

final class BackgroundMatrixProbe: @unchecked Sendable {
    private static let sentinel = "local.pokimcp.matrixsentinel"
    private static let queue = DispatchQueue(label: "poki.lab.background-matrix")
    @MainActor private static var started = false

    private let lock = NSLock()
    private var stopped = false
    private var locallyStopped = false
    private var path: URL {
        let root = URL.documentsDirectory.appending(path: "BackgroundMatrix", directoryHint: .isDirectory)
        guard isDeviceTrial else { return root }
        return root.appending(path: suite == .deviceSafety ? "safety" : "controls", directoryHint: .isDirectory)
    }
    private let native = PKInProcess.shared()
    private let suite: Suite
    private let attempt: Int
    private let build: String
    private let osBuild: String
    private let automated: Bool
    private let runID = UUID()
    private var automationActive = false
    private var isDeviceTrial: Bool { suite == .deviceSafety || suite == .deviceControls }
    private var sentinelBaseline: Int?
    private var watermarkSeen = false

    @MainActor static func start() {
        let defaults = UserDefaults.standard
        let attempt = defaults.integer(forKey: "pokiMatrixAttempt")
        guard !started, Bundle.main.bundleIdentifier == "nz.zheha.poki.lab",
              defaults.bool(forKey: "pokiBackgroundMatrix"),
              let mode = defaults.string(forKey: "pokiMatrixSuite"), let suite = Suite(rawValue: mode),
              suite != .deviceSafety, suite != .deviceControls, (1...100).contains(attempt) else { return }
        started = true
        let probe = Self(suite: suite, attempt: attempt, build: defaults.string(forKey: "pokiMatrixBuild") ?? "",
                         osBuild: defaults.string(forKey: "pokiMatrixOSBuild") ?? "")
        probe.execute { _ in }
    }

    #if DEBUG && POKI_BACKGROUND_MATRIX_DEVICE
    @MainActor static func startLocal(safety: Bool, automated: Bool,
                                     completion: @escaping @MainActor @Sendable (Bool) -> Void) -> Self? {
        guard Bundle.main.bundleIdentifier == "nz.zheha.poki.lab",
              UIDevice.current.userInterfaceIdiom == .phone,
              UIApplication.shared.applicationState == .active else { return nil }
        let defaults = UserDefaults.standard
        let probe = Self(suite: safety ? .deviceSafety : .deviceControls, attempt: 1,
                         build: defaults.string(forKey: "pokiMatrixBuild") ?? "",
                         osBuild: defaults.string(forKey: "pokiMatrixOSBuild") ?? "", automated: automated)
        probe.execute(completion: completion)
        return probe
    }
    #endif

    @MainActor private func execute(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        let token = UIApplication.shared.beginBackgroundTask(withName: "Poki Lab Matrix") { self.cancel() }
        Self.queue.async {
            let outcome = self.run()
            let cleaned: Bool
            if self.isDeviceTrial {
                cleaned = self.native.matrixCloseConfirmed()
            } else {
                _ = self.native.close()
                cleaned = true
            }
            try? self.phase(!cleaned ? "cleanup_unconfirmed" : outcome.hasOutput ? "done" : "output_failed")
            Task { @MainActor in
                if token != .invalid { UIApplication.shared.endBackgroundTask(token) }
                completion(cleaned && outcome.passed)
            }
        }
    }

    private init(suite: Suite, attempt: Int, build: String, osBuild: String, automated: Bool = false) {
        self.suite = suite; self.attempt = attempt; self.build = build; self.osBuild = osBuild
        self.automated = automated
    }

    func cancel(local: Bool = false) {
        lock.lock()
        stopped = true
        locallyStopped = locallyStopped || local
        lock.unlock()
    }

    private var userStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return locallyStopped
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped || stopFilePresent
    }

    private var stopFilePresent: Bool { FileManager.default.fileExists(atPath: path.appending(path: "stop").path) }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private func ms(_ start: TimeInterval) -> Int { Int((now - start) * 1_000) }

    private func phase(_ value: String) throws {
        try Data(value.utf8).write(to: path.appending(path: "phase"), options: .atomic)
    }

    private func front() -> (bundle: String, pid: Int32)? {
        guard let observed = native.matrixFront(),
              let bundle = observed["bundleId"] as? String, let pid = observed["pid"] as? NSNumber, pid.int32Value > 0 else { return nil }
        return (bundle, pid.int32Value)
    }

    private func openSession() -> Bool {
        if !isDeviceTrial { return native.prepare()["ok"] as? Bool == true }
        for seconds in [4, 7] {
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
                guard let self, self.native.authorizationWaitSeconds() >= 3,
                      (try? String(contentsOf: self.path.appending(path: "phase"), encoding: .utf8)) == "preparing"
                else { return }
                try? self.phase("awaiting_authorization")
            }
        }
        guard native.matrixPrepareLocal(), let active = front(),
              active.bundle == "nz.zheha.poki.lab", active.pid == getpid() else { return false }
        watermarkSeen = native.matrixWatermarkSeen()
        return true
    }

    private func identity(bundle: String, pid: Int32) -> Identity? {
        let generation = native.generation()
        let stamp = native.matrixProcessStart(pid)
        guard stamp != 0, native.matrixBundle(pid) == bundle,
              stamp == native.matrixProcessStart(pid), generation == native.generation() else { return nil }
        return Identity(bundle: bundle, pid: pid, processStart: stamp, generation: generation)
    }

    private func stage(_ phaseName: String, bundle: String, readySelector: String? = nil, previous: String? = nil) throws -> Identity {
        try phase(phaseName)
        let deadline = now + 12
        var sawTarget = false
        var sawIdentity = false
        while !cancelled, now < deadline {
            if let active = front() {
                if active.bundle != bundle {
                    if let previous, active.bundle != previous { throw Reason.foregroundChanged }
                    Thread.sleep(forTimeInterval: 0.12)
                    continue
                }
                sawTarget = true
                guard let id = identity(bundle: bundle, pid: active.pid) else {
                    if isDeviceTrial { throw Reason.identityChanged }
                    Thread.sleep(forTimeInterval: 0.12)
                    continue
                }
                sawIdentity = true
                if let readySelector {
                    if let snapshot = read(id), Element.unique(readySelector, in: snapshot.elements) != nil { return id }
                } else { return id }
            }
            Thread.sleep(forTimeInterval: 0.12)
        }
        throw cancelled ? Reason.cancelled : sawIdentity ? Reason.baselineUnconfirmed
            : sawTarget ? Reason.identityChanged : Reason.stagingTimeout
    }

    private struct Snapshot {
        let key = UUID()
        let issuedAt: TimeInterval
        let elements: [Element]
        let raw: [[String: Any]]
    }

    private func read(_ id: Identity) -> Snapshot? {
        guard native.generation() == id.generation, native.matrixProcessStart(id.pid) == id.processStart,
              let raw = native.matrixSnapshot(id.pid), native.matrixProcessStart(id.pid) == id.processStart,
              native.generation() == id.generation else { return nil }
        let items = raw.map {
            Element(id: $0["id"] as? String ?? "", label: $0["label"] as? String ?? "", value: $0["value"] as? String ?? "")
        }
        return Snapshot(issuedAt: now, elements: items, raw: raw)
    }

    private func witness(_ sentinel: Identity, target: Identity?) -> (Int?, Reason?) {
        guard let active = front() else { return (nil, .foregroundUnconfirmed) }
        if active.bundle == target?.bundle { return (nil, .targetBecameForeground) }
        guard active.bundle == sentinel.bundle, active.pid == sentinel.pid else { return (nil, .foregroundChanged) }
        guard let snapshot = read(sentinel), let counter = Element.unique("matrix.sentinel.events", in: snapshot.elements),
              let count = Int(counter.label.isEmpty ? counter.value : counter.label) else { return (nil, .foregroundUnconfirmed) }
        return (count, nil)
    }

    private func run() -> (hasOutput: Bool, passed: Bool) {
        do {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try phase("preparing")
            let output = path.appending(path: "run.jsonl")
            try Data().write(to: output, options: .atomic)
            let file = try FileHandle(forWritingTo: output)
            defer { try? file.close() }
            if suite == .deviceSafety {
                let began = now
                if !cancelled, openSession() {
                    automationActive = true
                    try phase("waiting_stop")
                    while !cancelled, now - began < 45 { Thread.sleep(forTimeInterval: 0.10) }
                }
                let stopped = automationActive && (userStopped || (automated && stopFilePresent))
                var timings = Timings()
                timings.total = ms(began)
                let row = deviceRow(index: 0, result: .classify(delivery: .notSent, matched: stopped,
                    reason: stopped ? nil : automationActive ? .stagingTimeout : .sessionUnavailable),
                    stage: .preflight, timings: timings)
                try file.write(contentsOf: row.jsonLine())
                return (true, stopped)
            }
            var target: Identity?
            var sentinel: Identity?
            var assertion: Assertion = .notMeasured
            var abort: Reason?
            let attachStart = now
            do {
                guard !cancelled else { throw Reason.cancelled }
                guard openSession() else { throw Reason.sessionUnavailable }
                automationActive = true
                if suite != .unseen {
                    let id = try stage("waiting_target", bundle: suite.bundle, readySelector: suite.readySelector,
                                       previous: isDeviceTrial ? "nz.zheha.poki.lab" : nil)
                    target = id
                    assertion = suite == .unasserted ? .notRequested : native.matrixHold(id.pid) ? .granted : .refused
                } else { assertion = .notRequested }
                sentinel = try stage("waiting_sentinel", bundle: Self.sentinel,
                                     previous: isDeviceTrial ? target?.bundle : nil)
                if assertion == .refused { throw Reason.assertionRefused }
                if isDeviceTrial, let sentinel {
                    let (count, reason) = witness(sentinel, target: target)
                    if let reason { throw reason }
                    guard let count, count == 0 else { throw Reason.sentinelInput }
                    sentinelBaseline = count
                }
            } catch {
                abort = error as? Reason ?? .sessionUnavailable
            }
            let attach = ms(attachStart)
            for (index, test) in suite.cases.enumerated() {
                let trial: Trial
                if let sentinel, abort == nil {
                    trial = run(test, target: target, sentinel: sentinel, assertion: assertion)
                    if trial.result.outcome == .safetyAbort || trial.result.delivery == .unknown
                        || (isDeviceTrial && ![.verified, .unsupported].contains(trial.result.outcome)) {
                        abort = .trialAborted
                    }
                } else {
                    trial = Trial(result: .classify(delivery: .notSent, matched: false, reason: abort ?? .sessionUnavailable), stage: .staging)
                }
                var timings = trial.timings
                if index == 0 { timings.attach = attach }
                let row = LogRow(runID: runID, suite: suite, caseIndex: index, attempt: attempt, build: build, osBuild: osBuild,
                                 result: trial.result, stage: trial.stage, targetBefore: trial.before, targetAfter: trial.after,
                                 assertion: assertion, foreground: trial.foreground, automationActive: automationActive,
                                 timings: timings, platform: isDeviceTrial ? .device : .simulator,
                                 watermarkSeen: watermarkSeen)
                try file.write(contentsOf: row.jsonLine())
            }
            return (true, abort == nil)
        } catch {
            return (false, false)
        }
    }

    private func deviceRow(index: Int, result: BackgroundMatrix.Result, stage: Stage, timings: Timings) -> LogRow {
        LogRow(runID: runID, suite: suite, caseIndex: index, attempt: attempt, build: build, osBuild: osBuild,
               result: result, stage: stage, targetBefore: .unknown, targetAfter: .unknown, assertion: .notRequested,
               foreground: Foreground(), automationActive: automationActive, timings: timings, platform: .device,
               watermarkSeen: watermarkSeen)
    }

    private struct Trial {
        var result: BackgroundMatrix.Result
        var stage: Stage
        var before: TargetState = .unknown
        var after: TargetState = .unknown
        var foreground = Foreground()
        var timings = Timings()
    }

    private func run(_ test: MatrixCase, target: Identity?, sentinel: Identity, assertion: Assertion) -> Trial {
        var state = Trial(result: .classify(delivery: .notSent, matched: false), stage: .preflight)
        let began = now
        var stage = Stage.preflight
        var delivery = Delivery.notSent
        var activity = 0
        var witnessed = 0
        var firstCounter = sentinelBaseline
        var hadInput = false
        func checkFront() throws {
            let (count, reason) = witness(sentinel, target: target)
            if let reason {
                if reason == .targetBecameForeground || reason == .foregroundChanged { activity += 1 }
                throw reason
            }
            if let count {
                witnessed += 1
                if let firstCounter, count != firstCounter { hadInput = true; throw Reason.sentinelInput }
                if firstCounter == nil { firstCounter = count }
            }
        }
        do {
            guard !cancelled else { throw Reason.cancelled }
            try checkFront()
            guard let target else { state.before = .unavailable; try checkFront(); throw Reason.targetNotSeen }
            guard test.op != .screenshot else { try checkFront(); throw Reason.screenshotUnavailable }
            stage = .snapshot
            let snapshotStart = now
            let before = read(target)
            state.timings.snapshotBefore = ms(snapshotStart)
            guard let before else { throw Reason.axUnavailable }
            if assertion == .granted { state.before = .backgroundRunning }
            if test.op == .look {
                stage = .verify
                try checkFront()
                let matched = test.verified(before: [], after: before.elements)
                state.result = .classify(delivery: .notSent, matched: matched, reason: matched ? nil : .elementUnavailable)
            } else if isDeviceTrial && test.negative {
                try checkFront()
                throw Reason.visibleTouch
            } else {
                let bars = before.raw.indices.filter { (before.raw[$0]["type"] as? NSNumber)?.intValue == 21 }
                let selected = test.op == .back ? (bars.count == 1 ? bars.first : nil) :
                    test.selector.flatMap { Element.index($0, in: before.elements) }
                guard let index = selected, let node = before.raw[index]["node"] else {
                    try checkFront()
                    throw Reason.elementUnavailable
                }
                stage = .preflight
                try checkFront()
                let ticket = ActionTicket(identity: target, snapshot: before.key, issuedAt: before.issuedAt)
                stage = .dispatch
                let dispatched = now
                let outcome = BackgroundMatrix.Result.oneDispatch(preflight: {
                    ticket.refusal(current: self.identity(bundle: target.bundle, pid: target.pid),
                                   snapshot: before.key, now: self.now, cancelled: self.cancelled)
                }, dispatch: {
                    let reply = self.native.matrixPerform(test.op.rawValue, node: node, pid: target.pid,
                                                          processStart: target.processStart, generation: target.generation,
                                                          validUntil: before.issuedAt + 3, preflight: {
                        if self.cancelled { return Reason.cancelled.rawValue }
                        if self.isDeviceTrial {
                            let (count, reason) = self.witness(sentinel, target: target)
                            if let reason { return reason.rawValue }
                            guard count == self.sentinelBaseline else { return Reason.sentinelInput.rawValue }
                        }
                        return self.cancelled ? Reason.cancelled.rawValue : nil
                    })
                    if reply == "sent" { return (.sent, nil) }
                    let reason = Reason(rawValue: reply) ?? .replyTimeout
                    return (reason == .replyTimeout ? .unknown : reason == .axActionRefused ? .sent : .notSent, reason)
                }, verify: { false }, negative: test.negative)
                delivery = outcome.delivery
                state.timings.dispatch = ms(dispatched)
                stage = .verify
                if delivery == .sent, outcome.reason == .noEffect {
                    let verifying = now
                    var matched = false
                    var sawReadback = false
                    for settle in [0.10, 0.35, 0.75] where !matched {
                        guard !cancelled else { throw Reason.cancelled }
                        Thread.sleep(forTimeInterval: settle)
                        if let after = read(target) {
                            sawReadback = true
                            matched = test.verified(before: before.elements, after: after.elements)
                        }
                    }
                    try checkFront()
                    state.timings.verify = ms(verifying)
                    state.result = .classify(delivery: .sent, matched: matched, reason: sawReadback ? nil : .effectUnverified,
                                             negative: test.negative)
                } else {
                    try checkFront()
                    stage = .dispatch
                    state.result = outcome
                }
            }
            if native.matrixProcessStart(target.pid) == target.processStart {
                state.after = delivery == .unknown ? .unknown : state.before
            } else { state.after = .unavailable }
        } catch {
            let reason = error as? Reason ?? .axUnavailable
            state.result = .classify(delivery: delivery, matched: false, reason: reason, negative: test.negative)
            if reason == .targetBecameForeground { state.after = .foreground }
        }
        state.stage = stage
        state.timings.total = ms(began)
        state.foreground = Foreground(observedSwitches: witnessed > 0 || activity > 0 ? activity : nil,
                                      telemetry: witnessed >= 2 ? .sampled : .incomplete,
                                      unexpectedInput: witnessed >= 2 ? hadInput : nil)
        return state
    }
}
#endif
