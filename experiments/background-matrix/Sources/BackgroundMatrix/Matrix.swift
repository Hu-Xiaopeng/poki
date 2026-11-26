import Foundation

public enum Suite: String, CaseIterable, Sendable {
    case controls, levelTwo = "level_two", swiftUI = "swiftui", web, unseen, unasserted, flutter, compose, reactNative = "react_native"

    public var alias: String {
        switch self {
        case .flutter, .compose, .reactNative: rawValue
        default: "ax_fixture"
        }
    }

    public var scenario: String {
        switch self {
        case .unseen: "unseen"
        case .unasserted: "warm_unasserted_other_app_front"
        default: "warm_asserted_other_app_front"
        }
    }

    public var bundle: String {
        switch self {
        case .flutter: "local.pokimcp.flutterfix"
        case .compose: "local.pokimcp.composefix"
        case .reactNative: "local.pokimcp.rnfix"
        default: "local.pokimcp.axfixture"
        }
    }

    public var readySelector: String? {
        switch self {
        case .controls, .unasserted: "matrix.plain"
        case .levelTwo: "Activate push"
        case .swiftUI: "sui.button"
        case .web: "WebButton"
        case .flutter: "FlutterButton"
        case .compose: "ComposeButton"
        case .reactNative: "press.plain"
        case .unseen: nil
        }
    }

    public var cases: [MatrixCase] {
        switch self {
        case .controls:
            [
                .init("uikit-read", "controls", .look, nil, .present("lastEvent")),
                .init("uikit-bar", "bar_item", .activate, "Bar", .changedSuffix("lastEvent", " matrix bar")),
                .init("uikit-plain", "plain_button", .activate, "matrix.plain", .changedSuffix("lastEvent", " button"), negative: true),
                .init("uikit-switch", "native_switch", .activate, "Switch", .changedSuffix("lastEvent", " switch true"), negative: true),
                .init("uikit-set", "text_field", .set, "field", .value("field", MatrixCase.sample)),
                .init("uikit-return", "text_field", .submit, "field", .changedSuffix("lastEvent", " return"), negative: true),
                .init("uikit-scroll", "table", .scroll, "bigTable", .increases("matrix.scroll.offset")),
                .init("uikit-screenshot", "display", .screenshot, nil, .none, negative: true)
            ]
        case .levelTwo:
            [.init("uikit-back", "navigation_bar", .back, nil, .appears("matrix.plain", removing: "Activate push"))]
        case .swiftUI:
            [.init("swiftui-button", "swiftui_button", .activate, "sui.button", .changedSuffix("lastEvent", " swiftui button"))]
        case .web:
            [.init("webkit-button", "webkit_button", .activate, "WebButton", .changedSuffix("lastEvent", " web button"), negative: true)]
        case .unseen, .unasserted:
            [.init("\(rawValue)-read", "controls", .look, nil, .present("lastEvent"))]
        case .flutter:
            [
                .init("flutter-read", "button", .look, nil, .present("FlutterButton")),
                .init("flutter-activate", "button", .activate, "FlutterButton", .changedSuffix("lastEvent", " elevated button")),
                .init("flutter-text", "text_field", .set, "FlutterField", .value("FlutterField", MatrixCase.sample)),
                .init("flutter-tab", "tab", .activate, "TabTwo*", .appears("TabTwoContent", removing: "FlutterButton"))
            ]
        case .compose:
            [
                .init("compose-read", "button", .look, nil, .present("ComposeButton")),
                .init("compose-activate", "button", .activate, "ComposeButton", .changedSuffix("lastEvent", " button")),
                .init("compose-text", "text_field", .set, "ComposeField", .value("ComposeField", MatrixCase.sample)),
                .init("compose-tab", "tab", .activate, "ComposeTabTwo", .appears("TabTwoContent", removing: "ComposeButton"))
            ]
        case .reactNative:
            [
                .init("rn-read", "button", .look, nil, .present("press.plain")),
                .init("rn-plain", "plain_pressable", .activate, "press.plain", .changedSuffix("lastEvent", " press plain"), negative: true),
                .init("rn-accessible", "accessible_pressable", .activate, "press.tap", .changedSuffix("lastEvent", " press onAccessibilityTap")),
                .init("rn-text", "text_field", .set, "RNField", .value("RNField", MatrixCase.sample)),
                .init("rn-tab", "tab", .activate, "RNTabTwo*", .appears("TabTwoContent", removing: "press.plain"), negative: true)
            ]
        }
    }
}

public enum Operation: String, Codable, Sendable { case look, activate, set, submit, scroll, back, screenshot }
public enum Delivery: String, Codable, Sendable { case notSent = "not_sent", sent, unknown }
public enum Outcome: String, Codable, Sendable {
    case verified, unsupported, blocked, timeout, unverified
    case notApplicable = "not_applicable", safetyAbort = "safety_abort"
}
public enum Verification: String, Codable, Sendable {
    case matched, notApplicable = "not_applicable", noExpectedEffect = "no_expected_effect"
    case unavailable, staleEvidence = "stale_evidence"
}
public enum Reason: String, Codable, Error, Sendable {
    case targetNotSeen = "target_not_seen", targetNotRunning = "target_not_running"
    case targetBecameForeground = "target_became_foreground", foregroundChanged = "foreground_changed"
    case foregroundUnconfirmed = "foreground_unconfirmed"
    case sentinelInput = "sentinel_input", sessionUnavailable = "session_unavailable"
    case identityChanged = "identity_changed", staleRef = "stale_ref", assertionRefused = "assertion_refused"
    case axUnavailable = "ax_unavailable", elementUnavailable = "element_unavailable", axActionRefused = "ax_action_refused"
    case visibleTouch = "requires_visible_touch", screenshotUnavailable = "live_screenshot_unsupported"
    case noEffect = "no_effect", effectUnverified = "effect_unverified", replyTimeout = "reply_timeout"
    case cancelled, trialAborted = "trial_aborted", stagingTimeout = "staging_timeout"
    case baselineUnconfirmed = "fixture_baseline_unconfirmed"
}

public struct MatrixCase: Sendable {
    public enum Check: Sendable {
        case none, present(String), changedSuffix(String, String), value(String, String)
        case increases(String), appears(String, removing: String)
    }

    public static let sample = "Poki Matrix 42"
    public let id: String
    public let control: String
    public let op: Operation
    public let selector: String?
    public let check: Check
    public let negative: Bool

    public init(_ id: String, _ control: String, _ op: Operation, _ selector: String?, _ check: Check, negative: Bool = false) {
        self.id = id; self.control = control; self.op = op; self.selector = selector; self.check = check; self.negative = negative
    }

    public func verified(before: [Element], after: [Element]) -> Bool {
        func display(_ element: Element?) -> String? {
            guard let element else { return nil }
            return element.label.isEmpty ? element.value : element.label
        }
        switch check {
        case .none: return false
        case .present(let key): return Element.unique(key, in: after) != nil
        case .changedSuffix(let key, let suffix):
            guard let old = display(Element.unique(key, in: before)), let new = display(Element.unique(key, in: after)) else { return false }
            return old != new && new.hasSuffix(suffix)
        case .value(let key, let expected):
            return Element.unique(key, in: before)?.value != expected && Element.unique(key, in: after)?.value == expected
        case .increases(let key):
            guard let old = display(Element.unique(key, in: before)).flatMap(Int.init),
                  let new = display(Element.unique(key, in: after)).flatMap(Int.init) else { return false }
            return new > old
        case .appears(let key, let gone):
            return Element.unique(gone, in: before) != nil && Element.unique(key, in: before) == nil &&
                Element.unique(key, in: after) != nil && Element.unique(gone, in: after) == nil
        }
    }
}

public struct Element: Sendable {
    public let id: String
    public let label: String
    public let value: String

    public init(id: String, label: String, value: String) {
        self.id = id; self.label = label; self.value = value
    }

    public static func index(_ key: String, in elements: [Self]) -> Int? {
        let byID = elements.indices.filter { elements[$0].id == key }
        let matches = byID.isEmpty ? elements.indices.filter {
            key.hasSuffix("*") ? elements[$0].label.hasPrefix(key.dropLast()) : elements[$0].label == key
        } : byID
        return matches.count == 1 ? matches[0] : nil
    }

    public static func unique(_ key: String, in elements: [Self]) -> Self? {
        index(key, in: elements).map { elements[$0] }
    }
}

public struct Identity: Equatable, Sendable {
    public let bundle: String
    public let pid: Int32
    public let processStart: UInt64
    public let generation: UInt64

    public init(bundle: String, pid: Int32, processStart: UInt64, generation: UInt64) {
        self.bundle = bundle; self.pid = pid; self.processStart = processStart; self.generation = generation
    }
}

public struct ActionTicket: Sendable {
    public let identity: Identity
    public let snapshot: UUID
    public let issuedAt: TimeInterval

    public init(identity: Identity, snapshot: UUID, issuedAt: TimeInterval) {
        self.identity = identity; self.snapshot = snapshot; self.issuedAt = issuedAt
    }

    public func refusal(current: Identity?, snapshot: UUID, now: TimeInterval, cancelled: Bool) -> Reason? {
        if cancelled { return .cancelled }
        guard let current else { return .targetNotRunning }
        guard current == identity else { return .identityChanged }
        guard snapshot == self.snapshot, now >= issuedAt, now - issuedAt <= 3 else { return .staleRef }
        return nil
    }
}

public struct Result: Equatable, Sendable {
    public let outcome: Outcome
    public let delivery: Delivery
    public let verification: Verification
    public let reason: Reason?

    public static func classify(delivery: Delivery, matched: Bool, reason: Reason? = nil, negative: Bool = false) -> Self {
        if let reason, [.cancelled, .targetBecameForeground, .foregroundChanged, .foregroundUnconfirmed, .sentinelInput, .identityChanged, .staleRef].contains(reason) {
            return .init(outcome: .safetyAbort, delivery: delivery, verification: .unavailable, reason: reason)
        }
        if delivery == .unknown {
            return .init(outcome: .unverified, delivery: delivery, verification: .unavailable, reason: reason ?? .replyTimeout)
        }
        if matched {
            return .init(outcome: .verified, delivery: delivery, verification: .matched, reason: nil)
        }
        if let reason {
            let outcome: Outcome = switch reason {
            case .screenshotUnavailable, .visibleTouch, .elementUnavailable, .axActionRefused: .unsupported
            case .trialAborted, .baselineUnconfirmed: .notApplicable
            case .effectUnverified: .unverified
            case .replyTimeout, .stagingTimeout: .timeout
            default: .blocked
            }
            return .init(outcome: outcome, delivery: delivery, verification: .notApplicable, reason: reason)
        }
        return .init(outcome: negative ? .unsupported : .unverified, delivery: delivery, verification: .noExpectedEffect, reason: .noEffect)
    }

    public static func oneDispatch(
        preflight: () -> Reason?, dispatch: () -> (Delivery, Reason?), verify: () -> Bool, negative: Bool = false
    ) -> Self {
        if let reason = preflight() { return classify(delivery: .notSent, matched: false, reason: reason, negative: negative) }
        let (delivery, reason) = dispatch()
        return classify(delivery: delivery, matched: delivery == .sent && reason == nil && verify(), reason: reason, negative: negative)
    }
}
