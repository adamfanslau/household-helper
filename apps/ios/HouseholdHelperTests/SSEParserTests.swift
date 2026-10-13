import Foundation
import Testing
@testable import HouseholdHelper

struct SSEParserTests {
    @Test func parsesFramesCommentsAndMultilineData() {
        var p = SSEParser()
        var frames: [SSEFrame] = []
        for line in ["event: ready", "data: {\"household_id\":\"h\"}", "", ": ping", "", "id: e1", "event: change", "data: {\"a\":", "data: 1}", "", "retry: 5000", ""] {
            if let f = p.feed(line: line) { frames.append(f) }
        }
        #expect(frames.count == 2)
        #expect(frames[0] == SSEFrame(event: "ready", id: nil, data: "{\"household_id\":\"h\"}"))
        #expect(frames[1] == SSEFrame(event: "change", id: "e1", data: "{\"a\":\n1}"))
    }

    @Test func defaultsToMessageAndTrimsOneSpace() {
        var p = SSEParser()
        #expect(p.feed(line: "data:  two spaces") == nil)
        #expect(p.feed(line: "") == SSEFrame(event: "message", id: nil, data: " two spaces"))
    }
}
