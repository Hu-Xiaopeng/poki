import Foundation

public enum Telemetry: String, Codable, Sendable {
    case sampled, incomplete, notMeasured = "not_measured"
}

public struct Foreground: Encodable, Sendable {
    public let expected = "matrix_sentinel"
    public var observedSwitches: Int?
    public var telemetry: Telemetry
    public var unexpectedInput: Bool?

    public init(observedSwitches: Int? = nil, telemetry: Telemetry = .notMeasured, unexpectedInput: Bool? = nil) {
        self.observedSwitches = observedSwitches; self.telemetry = telemetry; self.unexpectedInput = unexpectedInput
    }

    private enum CodingKeys: String, CodingKey { case expected, observedSwitches, telemetry, unexpectedInput }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(expected, forKey: .expected)
        try box.encode(observedSwitches, forKey: .observedSwitches)
        try box.encode(telemetry, forKey: .telemetry)
        try box.encode(unexpectedInput, forKey: .unexpectedInput)
    }
}

public struct Timings: Encodable, Sendable {
    public var attach: Int?
    public var snapshotBefore: Int?
    public var dispatch: Int?
    public var verify: Int?
    public var total: Int?

    public init() {}

    private enum CodingKeys: String, CodingKey { case attach, snapshotBefore, dispatch, verify, total }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(attach, forKey: .attach)
        try box.encode(snapshotBefore, forKey: .snapshotBefore)
        try box.encode(dispatch, forKey: .dispatch)
        try box.encode(verify, forKey: .verify)
        try box.encode(total, forKey: .total)
    }
}

public enum Stage: String, Codable, Sendable { case staging, snapshot, preflight, dispatch, verify }
public enum Assertion: String, Codable, Sendable { case granted, refused, notRequested = "not_requested", notMeasured = "not_measured" }
public enum TargetState: String, Codable, Sendable { case backgroundRunning = "background_running", foreground, unavailable, unknown }

public struct LogRow: Encodable, Sendable {
    public struct ErrorCode: Encodable, Sendable {
        public let stage: Stage
        public let domain: String
        public let code: Reason
        public let reason: Reason

        init(_ reason: Reason, stage: Stage) {
            self.stage = stage; self.reason = reason; self.code = reason
            self.domain = reason == .axActionRefused || reason == .axUnavailable ? "AX" : "matrix"
        }
    }

    public let schema = 1
    public let fixtureVersion = "1"
    public let platform = "iphone-simulator"
    public let route = "lab_ax"
    public let runID: UUID
    public let caseID: String
    public let attempt: Int
    public let build: String
    public let osBuild: String
    public let scenario: String
    public let app: String
    public let control: String
    public let op: Operation
    public let targetBefore: TargetState
    public let targetAfter: TargetState
    public let assertion: Assertion
    public let foreground: Foreground
    public let automationMode: String
    public let watermark = "not_measured"
    public let liveActivity = "not_measured"
    public let delivery: Delivery
    public let verification: Verification
    public let outcome: Outcome
    public let error: ErrorCode?
    public let ms: Timings

    public init(runID: UUID, suite: Suite, caseIndex: Int, attempt: Int, build: String, osBuild: String, result: Result,
                stage: Stage, targetBefore: TargetState, targetAfter: TargetState, assertion: Assertion, foreground: Foreground,
                automationActive: Bool, timings: Timings) {
        let test = suite.cases[caseIndex]
        self.runID = runID; self.caseID = test.id; self.attempt = attempt
        self.build = Self.normalized(build, pattern: "^[0-9a-f]{7,40}$")
        self.osBuild = Self.normalized(osBuild, pattern: "^[0-9]{2}[A-Z][0-9]{1,5}[a-z]?$")
        self.scenario = suite.scenario; self.app = suite.alias; self.control = test.control; self.op = test.op
        self.targetBefore = targetBefore; self.targetAfter = targetAfter; self.assertion = assertion; self.foreground = foreground
        self.automationMode = automationActive ? "active" : "not_measured"
        self.delivery = result.delivery; self.verification = result.verification; self.outcome = result.outcome
        self.error = result.reason.map { ErrorCode($0, stage: stage) }; self.ms = timings
    }

    private static func normalized(_ value: String, pattern: String) -> String {
        guard value.utf8.count <= 40, value.range(of: pattern, options: [.regularExpression, .anchored]) == value.startIndex..<value.endIndex else {
            return "unknown"
        }
        return value
    }

    public func jsonLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self) + Data([10])
    }

}
