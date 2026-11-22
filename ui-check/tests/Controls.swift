import XCTest

@MainActor
final class Controls: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.github.arkadeleon.ragnarok-offline")
    func start() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["roster-2"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["roster-2"].tap()
    }
    func movePanel(_ title: String) {
        let h = app.staticTexts[title].firstMatch
        XCTAssertTrue(h.waitForExistence(timeout: 5), app.debugDescription)
        let from = h.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5))
        from.press(forDuration: 0.2, thenDragTo: from.withOffset(CGVector(dx: -108, dy: 112)))
    }
    func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }
    func tap(_ label: String) {
        let b = button(label)
        XCTAssertTrue(b.waitForExistence(timeout: 4), "\(label)\n\(app.debugDescription)")
        XCTAssertTrue(b.isEnabled, label)
        b.tap()
    }
    func menu(_ stem: String) {
        let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@",stem)).firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 4), app.debugDescription)
        b.tap()
    }
    func testPartyOrdersAndManagement() {
        start()
        tap("Stop"); tap("Follow"); tap("Assist")
        tap("Reserve"); tap("Summon"); tap("Reserve")
        menu("Manage"); tap("Recruit")
        for job in ["Swordman","Acolyte","Mage","Archer"] { XCTAssertTrue(button(job).exists,app.debugDescription) }
        tap("Archer")
        menu("Manage"); menu("Release")
        if button("Cancel").waitForExistence(timeout: 3) {
            tap("Cancel")
        } else if button("Release").exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.08,dy: 0.87)).tap()
        } else {
            XCTFail(app.debugDescription)
        }
        menu("Manage"); tap("Refresh")
        menu("Manage"); tap("Create Party")
    }
    func testTeamModesAndSettings() {
        start()
        menu("Team"); tap("Nearby Hunt")
        menu("Team"); tap("Assist")
        menu("Team"); tap("Mob"); tap("Retreat")
        menu("Team"); tap("Assist")
        tap("Reserve"); tap("Settings"); movePanel("Companion Settings")
        menu("Two-Handed Sword"); tap("Spear")
        menu("Custom"); tap("Protect")
        menu("Normal"); tap("Quiet")
        menu("5"); tap("7")
        let f = app.textFields.firstMatch
        if !f.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(f.exists)
        menu("Close Companion Settings")
    }
    func testEquipmentAndSkills() {
        start()
        tap("Stop"); tap("Details"); movePanel("AI-Knight-2")
        tap("slot-2"); tap("Unequip")
        tap("gear:1"); tap("Equip")
        tap("Skills")
        tap("AI On"); tap("AI Off")
        tap("Info"); tap("OK")
        tap("Refresh")
        tap("Close AI-Knight-2")
    }
    func testBagAndSupplies() {
        start()
        tap("Reserve"); tap("Details"); movePanel("AI-Knight-2")
        tap("Your Bag"); tap("bag:5:101"); tap("Give")
        tap("supplybag:7:501"); tap("+"); tap("−"); tap("Give")
        tap("Supplies"); tap("supply:501"); tap("Return")
        tap("Gear"); tap("slot-2"); tap("Return")
    }
}
