import Foundation
import Testing
@testable import HouseholdHelper

struct PushPayloadTests {
    @Test func parsesTheServerKeys() {
        let p = PushPayload(userInfo: ["aps": ["alert": ["title": "Mock Household"]], "household_id": "h1", "type": "shopping_list_items.insert"])
        #expect(p == PushPayload(householdID: "h1", type: "shopping_list_items.insert"))
    }

    @Test func rejectsPayloadsWithoutAHousehold() {
        #expect(PushPayload(userInfo: ["aps": ["alert": "hi"]]) == nil)
        #expect(PushPayload(userInfo: ["household_id": ""]) == nil)
        #expect(PushPayload(userInfo: ["household_id": "h1"])?.type == "")
    }
}
