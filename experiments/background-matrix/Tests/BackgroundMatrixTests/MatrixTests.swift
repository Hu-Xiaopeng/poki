import BackgroundMatrix
import Foundation
import Testing

@Test func distinguishesVerifiedRejectionAndMissingEvidence() {
    #expect(BackgroundMatrix.Result.classify(delivery: .sent, matched: true).outcome == .verified)
    #expect(BackgroundMatrix.Result.classify(delivery: .sent, matched: false).outcome == .unverified)
    #expect(BackgroundMatrix.Result.classify(delivery: .sent, matched: false, reason: .axActionRefused).outcome == .unsupported)
    #expect(BackgroundMatrix.Result.classify(delivery: .notSent, matched: false, reason: .targetNotSeen).outcome == .blocked)
}

@Test func refusesStaleReferenceAndReusedPID() {
    let identity = Identity(bundle: "fixture", pid: 27, processStart: 1, generation: 9)
    let replacement = Identity(bundle: "fixture", pid: 27, processStart: 2, generation: 9)
    let snapshot = UUID()
    let ticket = ActionTicket(identity: identity, snapshot: snapshot, issuedAt: 8)
    #expect(ticket.refusal(current: identity, snapshot: snapshot, now: 9, cancelled: false) == nil)
    #expect(ticket.refusal(current: replacement, snapshot: snapshot, now: 9, cancelled: false) == .identityChanged)
    #expect(ticket.refusal(current: identity, snapshot: UUID(), now: 9, cancelled: false) == .staleRef)
    #expect(ticket.refusal(current: identity, snapshot: snapshot, now: 12, cancelled: false) == .staleRef)
}

@Test func cancelledPreflightNeverDispatches() {
    let result = BackgroundMatrix.Result.oneDispatch(preflight: { .cancelled }, dispatch: {
        Issue.record("Cancelled operation dispatched")
        return (.sent, nil)
    }, verify: {
        Issue.record("Cancelled operation tried readback")
        return true
    })
    #expect(result.delivery == .notSent)
    #expect(result.outcome == .safetyAbort)
}

@Test func unknownDeliveryDoesNotReplayOrClaimSuccess() {
    var dispatched = 0
    let result = BackgroundMatrix.Result.oneDispatch(preflight: { nil }, dispatch: {
        dispatched += 1
        return (.unknown, .replyTimeout)
    }, verify: {
        Issue.record("Unknown delivery treated as verified")
        return true
    })
    #expect(dispatched == 1)
    #expect(result.delivery == .unknown)
    #expect(result.outcome == .unverified)
}

@Test func verifiesTheSpecificEffectAndRefusesAmbiguousSelectors() {
    let original = Element(id: "lastEvent", label: "1 start", value: "")
    let unrelated = Element(id: "lastEvent", label: "2 scene change", value: "")
    let callback = Element(id: "lastEvent", label: "3 matrix bar", value: "")
    let test = Suite.controls.cases.first { $0.id == "uikit-bar" }!
    #expect(!test.verified(before: [original], after: [unrelated]))
    #expect(test.verified(before: [original], after: [callback]))
    #expect(!test.verified(before: [original], after: [callback, unrelated]))
    #expect(Element.index("lastEvent", in: [callback, unrelated]) == nil)
}

@Test func emitsOneSanitizedSchemaOneLine() throws {
    let result = BackgroundMatrix.Result.classify(delivery: .unknown, matched: false, reason: .replyTimeout)
    let row = LogRow(runID: UUID(), suite: .controls, caseIndex: 0, attempt: 1,
                     build: "SECRET input", osBuild: "24C5049d\nSECRET", result: result, stage: .dispatch,
                     targetBefore: .backgroundRunning, targetAfter: .unknown, assertion: .granted, foreground: Foreground(),
                     automationActive: true, timings: Timings())
    let data = try row.jsonLine()
    #expect(data.last == 10)
    #expect(data.filter { $0 == 10 }.count == 1)
    #expect(!String(decoding: data, as: UTF8.self).contains("SECRET"))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["schema"] as? Int == 1)
    #expect(json["run_id"] is String)
    #expect(json["case_id"] as? String == "uikit-read")
    #expect(json["build"] as? String == "unknown")
    #expect(json["os_build"] as? String == "unknown")
    #expect(json["delivery"] as? String == "unknown")
    #expect(((json["error"] as? [String: Any])?["reason"]) as? String == "reply_timeout")
    #expect(((json["ms"] as? [String: Any])?["total"]) is NSNull)
    #expect(((json["foreground"] as? [String: Any])?["unexpected_input"]) is NSNull)
}
