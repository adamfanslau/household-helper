// Regression smoke test driven through XCUITest. Needs the local stack with a FRESH seed
// (scripts/dev/stack.sh reset) and the Debug (emulator) build: scripts/dev/ios.sh uitest SmokeTests
import XCTest

final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HH_UITEST_USER"] = "alice"
        app.launch()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)", file: file, line: line)
    }

    /// Rows are default-style Buttons (see ListView); swipe buttons appear only on a partial swipe.
    private func item(_ name: String) -> XCUIElement { app.buttons["list.item.\(name)"] }

    func testListShopsAndSettingsFlow() {
        wait(item("Milk"))
        shot("01-list")

        // Add "Oat milk" → Unsorted.
        let input = app.textFields["list.input"]
        wait(input)
        input.tap()
        input.typeText("Oat milk\n")
        wait(item("Oat milk"))
        shot("02-added")

        // Tap → bought → under Recently bought (expand it).
        item("Oat milk").tap()
        wait(app.buttons["list.bought.toggle"])
        if !item("Oat milk").exists || !item("Oat milk").isHittable {
            // Section-header buttons fail XCUITest's hittable check; a coordinate tap works.
            app.buttons["list.bought.toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        wait(item("Oat milk"))
        XCTAssertTrue(item("Oat milk").label.contains("bought"), "label: \(item("Oat milk").label)")
        shot("03-bought")

        // Swipe trailing → delete (full swipe or the revealed button) → undo toast → gone.
        item("Oat milk").swipeLeft()
        let deleteButton = app.buttons["list.item.Oat milk.delete"]
        if deleteButton.waitForExistence(timeout: 2) { deleteButton.tap() }
        wait(app.buttons["list.undo"], 5)
        XCTAssertFalse(item("Oat milk").exists)
        shot("04-deleted")

        // Shops → Trader Joe's → tap Bananas (To list) → back on List: a second Bananas under TJ.
        app.tabBars.buttons["Shops"].tap()
        wait(app.buttons["shops.row.Trader Joe's"].firstMatch)
        app.buttons["shops.row.Trader Joe's"].firstMatch.tap()
        wait(app.buttons["shop.toList.Bananas"])
        app.buttons["shop.toList.Bananas"].tap()
        shot("05-to-list")
        app.tabBars.buttons["List"].tap()
        let bananas = app.buttons.matching(identifier: "list.item.Bananas")
        let deadline = Date().addingTimeInterval(10)
        while bananas.count < 2 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertGreaterThanOrEqual(bananas.count, 2, "To list should add a second Bananas under Trader Joe's")

        // Settings shows the seeded invite code.
        app.tabBars.buttons["Settings"].tap()
        wait(app.staticTexts["settings.inviteCode"])
        XCTAssertTrue(app.staticTexts["settings.inviteCode"].label.replacingOccurrences(of: " ", with: "").contains("MOCK1234"),
                      "invite label: \(app.staticTexts["settings.inviteCode"].label)")
        shot("06-settings")
    }
}
