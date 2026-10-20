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

        // Floating + → add sheet → "Oat milk" with no shop → Unsorted.
        wait(app.buttons["list.add"])
        app.buttons["list.add"].tap()
        let input = app.textFields["list.input"]
        wait(input)
        input.typeText("Oat milk")
        app.buttons["list.submit"].tap()
        wait(item("Oat milk"))
        shot("02-added")

        // Tap → in the basket (stays in Unsorted, ticked) → Checkout Unsorted → bought under Recently bought.
        item("Oat milk").tap()
        wait(app.buttons["list.checkout.Unsorted"])
        XCTAssertTrue(item("Oat milk").label.contains("in basket"), "label: \(item("Oat milk").label)")
        shot("03-basket")
        // Section-header buttons fail XCUITest's hittable check; a coordinate tap works.
        app.buttons["list.checkout.Unsorted"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        wait(app.buttons["list.bought.toggle"])
        if !item("Oat milk").exists || !item("Oat milk").isHittable {
            app.buttons["list.bought.toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        wait(item("Oat milk"))
        XCTAssertTrue(item("Oat milk").label.contains("bought"), "label: \(item("Oat milk").label)")
        shot("03-bought")

        // Swipe trailing → delete (full swipe or the revealed button) → undo toast → gone.
        // The row sits at the bottom edge after expanding Recently bought: bring it above the
        // floating tab bar and the + button first, or the revealed Delete lands under them.
        if item("Oat milk").frame.maxY > app.frame.maxY - 140 {
            app.swipeUp()
            _ = item("Oat milk").waitForExistence(timeout: 2)
        }
        item("Oat milk").swipeLeft()
        let deleteButton = app.buttons["list.item.Oat milk.delete"]
        if deleteButton.waitForExistence(timeout: 2) { deleteButton.tap() }
        wait(app.buttons["list.undo"], 5)
        XCTAssertFalse(item("Oat milk").exists)
        shot("04-deleted")

        // Add sheet with a typing hint: "Chi" suggests Chicken breast (last shop Costco) → under Costco.
        app.buttons["list.add"].tap()
        wait(input)
        input.typeText("Chi")
        wait(app.buttons["list.suggestion.Chicken breast"])
        app.buttons["list.suggestion.Chicken breast"].tap()
        app.buttons["list.submit"].tap()
        wait(item("Chicken breast"))
        shot("05-from-hint")

        // Shops → Costco shows it as still needed.
        app.tabBars.buttons["Shops"].tap()
        wait(app.buttons["shops.row.Costco"].firstMatch)
        app.buttons["shops.row.Costco"].firstMatch.tap()
        wait(app.buttons["shop.row.Chicken breast"])
        app.tabBars.buttons["List"].tap()

        // The Household tab shows the seeded invite code.
        app.tabBars.buttons["Household"].tap()
        wait(app.staticTexts["settings.inviteCode"])
        XCTAssertTrue(app.staticTexts["settings.inviteCode"].label.replacingOccurrences(of: " ", with: "").contains("MOCK1234"),
                      "invite label: \(app.staticTexts["settings.inviteCode"].label)")
        shot("06-settings")
    }
}
