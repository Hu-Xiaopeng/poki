#if POKI_BACKGROUND_MATRIX && targetEnvironment(simulator)
import BackgroundMatrix
import Foundation
import UIKit

final class BackgroundMatrixProbe: @unchecked Sendable {
    private static let sentinel = "local.pokimcp.matrixsentinel"
    private static let queue = DispatchQueue(label: "poki.lab.background-matrix")
    @MainActor private static var started = false

    private let lock = NSLock()
    private var stopped = false
    private let path = URL.documentsDirectory.appending(path: "BackgroundMatrix", directoryHint: .isDirectory)
    private let native = PKInProcess.shared()
    private let suite: Suite
    private let attempt: Int
    private let build: String
    private let osBuild: String
    private let runID = UUID()
    private var automationActive = false

    @MainActor static func start() {
        let defaults = UserDefaults.standard
        let attempt = defaults.integer(forKey: "pokiMatrixAttempt")
        guard !started, Bundle.main.bundleIdentifier == "nz.zheha.poki.lab",
              defaults.bool(forKey: "pokiBackgroundMatrix"),
              let mode = defaults.string(forKey: "pokiMatrixSuite"), let suite = Suite(rawValue: mode),
              (1...100).contains(attempt) else { return }
        started = true
        let probe = Self(suite: suite, attempt: attempt, build: defaults.string(forKey: "pokiMatrixBuild") ?? "",
                         osBuild: defaults.string(forKey: "pokiMatrixOSBuild") ?? "")
        let token = UIApplication.shared.beginBackgroundTask(withName: "Poki Lab Matrix") { probe.cancel() }
        queue.async {
            probe.run()
            Task { @MainActor in
                if token != .invalid { UIApplication.shared.endBackgroundTask(token) }
            }
        }
    }

    private init(suite: Suite, attempt: Int, build: String, osBuild: String) {
        self.suite = suite; self.attempt = attempt; self.build = build; self.osBuild = osBuild
    }

    private func cancel() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped || FileManager.default.fileExists(atPath: path.appending(path: "stop").path)
    }

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

    private func identity(bundle: String, pid: Int32) -> Identity? {
        let generation = native.generation()
        let stamp = native.matrixProcessStart(pid)
        guard stamp != 0, native.matrixBundle(pid) == bundle,
              stamp == native.matrixProcessStart(pid), generation == native.generation() else { return nil }
        return Identity(bundle: bundle, pid: pid, processStart: stamp, generation: generation)
    }

    private func stage(_ phaseName: String, bundle: String, readySelector: String? = nil) throws -> Identity {
        try phase(phaseName)
        let deadline = now + 12
        var sawTarget = false
        while !cancelled, now < deadline {
            if let active = front(), active.bundle == bundle, let id = identity(bundle: bundle, pid: active.pid) {
                sawTarget = true
                if let readySelector {
                    if let snapshot = read(id), Element.unique(readySelector, in: snapshot.elements) != nil { return id }
                } else { return id }
            }
            Thread.sleep(forTimeInterval: 0.12)
        }
        throw cancelled ? Reason.cancelled : sawTarget ? Reason.baselineUnconfirmed : Reason.stagingTimeout
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

    private func run() {
        do {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try phase("preparing")
            let output = path.appending(path: "run.jsonl")
            try Data().write(to: output, options: .atomic)
            let file = try FileHandle(forWritingTo: output)
            defer { try? file.close() }
            defer {
                _ = native.close()
                try? phase("done")
            }
            var target: Identity?
            var sentinel: Identity?
            var assertion: Assertion = .notMeasured
            var abort: Reason?
            let attachStart = now
            do {
                guard !cancelled else { throw Reason.cancelled }
                guard native.prepare()["ok"] as? Bool == true else { throw Reason.sessionUnavailable }
                automationActive = true
                if suite != .unseen {
                    let id = try stage("waiting_target", bundle: suite.bundle, readySelector: suite.readySelector)
                    target = id
                    assertion = suite == .unasserted ? .notRequested : native.matrixHold(id.pid) ? .granted : .refused
                } else { assertion = .notRequested }
                sentinel = try stage("waiting_sentinel", bundle: Self.sentinel)
                if assertion == .refused { throw Reason.assertionRefused }
            } catch {
                abort = error as? Reason ?? .sessionUnavailable
            }
            let attach = ms(attachStart)
            for (index, test) in suite.cases.enumerated() {
                let trial: Trial
                if let sentinel, abort == nil {
                    trial = run(test, target: target, sentinel: sentinel, assertion: assertion)
                    if trial.result.outcome == .safetyAbort || trial.result.delivery == .unknown { abort = .trialAborted }
                } else {
                    trial = Trial(result: .classify(delivery: .notSent, matched: false, reason: abort ?? .sessionUnavailable), stage: .staging)
                }
                var timings = trial.timings
                if index == 0 { timings.attach = attach }
                let row = LogRow(runID: runID, suite: suite, caseIndex: index, attempt: attempt, build: build, osBuild: osBuild,
                                 result: trial.result, stage: trial.stage, targetBefore: trial.before, targetAfter: trial.after,
                                 assertion: assertion, foreground: trial.foreground, automationActive: automationActive, timings: timings)
                try file.write(contentsOf: row.jsonLine())
            }
        } catch {
            try? phase("output_failed")
        }
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
        var firstCounter: Int?
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
                                                          validUntil: before.issuedAt + 3, allowed: { !self.cancelled })
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
