import XCTest

/// End-to-end flows against demo mode (`-demo`): fixture data, no network, no accounts created.
/// Case ids match replica/test-plan.md.
final class minceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: helpers

    private func launch(_ args: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + args
        app.launch()
        return app
    }

    /// Tab items sometimes report a degenerate hit point; tap the frame centre instead.
    private func forceTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    private func openPlus(_ app: XCUIApplication, pick title: String) {
        app.buttons["Add to diary"].firstMatch.tap()
        // Gold actions read "Photo, Gold feature" for Basic users.
        let action = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "plus menu should list \(title)")
        action.tap()
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Tap the trailing edge so the cursor lands after existing text (number fields are right-aligned).
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    // MARK: F06 review the day

    func testF06_H1_diaryShowsGroupsEntriesAndTotals() {
        let app = launch("-gold", "-tab", "diary")
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Oats, rolled, dry"].exists)
        XCTAssertTrue(app.staticTexts["Eaten"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Breakfast'")).firstMatch.exists)   // Gold adds "· 294 kcal"
        XCTAssertTrue(scrollTo(app.staticTexts["Vitamins"], in: app), "nutrient tables should be on the diary")
    }

    func testF06_H2_tapNutrientShowsSources() {
        let app = launch("-gold", "-tab", "diary")
        let magnesium = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Magnesium'")).firstMatch
        XCTAssertTrue(scrollTo(magnesium, in: app))
        magnesium.tap()
        XCTAssertTrue(app.navigationBars["Magnesium"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Where it came from"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Oats, rolled, dry"].waitForExistence(timeout: 5), "oats supplied magnesium today")
    }

    func testF06_E1_previousDayNavigation() {
        let app = launch("-tab", "diary")
        app.buttons["Previous day"].firstMatch.tap()
        // Reads "Yesterday, Day complete" when the fixture marks it complete.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Yesterday'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Blueberries, raw"].exists, "yesterday's fixture has no blueberries")
    }

    // MARK: F02 log a food by search

    func testF02_H1_logFoodBySearchAddsEntry() {
        let app = launch("-tab", "diary")
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        openPlus(app, pick: "Food")
        let search = app.searchFields["Search foods"]
        type("salmon", into: search)
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Salmon, Atlantic, baked'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        app.buttons["Log"].tap()
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        // The fixture already has salmon at dinner; a second row means the new entry landed.
        let second = app.staticTexts.matching(NSPredicate(format: "label == 'Salmon, Atlantic, baked'")).element(boundBy: 1)
        XCTAssertTrue(scrollTo(second, in: app), "logged salmon should appear as a second row")
    }

    func testF02_E1_zeroAmountCannotBeLogged() {
        let app = launch("-tab", "diary", "-sheet", "food")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Oats, rolled, dry'")).firstMatch.tap()
        let amount = app.textFields.firstMatch
        type("0", into: amount)
        XCTAssertFalse(app.buttons["Log"].isEnabled)
        XCTAssertTrue(app.staticTexts["Enter an amount above zero."].exists)
    }

    func testF02_E2_deleteThenUndoRestoresEntry() {
        let app = launch("-tab", "diary")
        let oats = app.staticTexts["Oats, rolled, dry"]
        XCTAssertTrue(oats.waitForExistence(timeout: 5))
        oats.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Entry deleted"].waitForExistence(timeout: 3))
        XCTAssertFalse(oats.exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(oats.waitForExistence(timeout: 5), "undo should bring the entry back")
    }

    // MARK: F09 quick entries

    func testF09_H1_quickAdd() {
        let app = launch("-tab", "diary")
        openPlus(app, pick: "Quick add")
        type("Birthday cake", into: app.textFields["Label (optional)"])
        type("350", into: app.textFields.element(boundBy: 1))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollTo(app.staticTexts["Birthday cake"], in: app))
    }

    func testF09_H2_exerciseEstimatesEnergy() {
        let app = launch("-tab", "diary")
        openPlus(app, pick: "Exercise")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Running, 6 mph'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Estimated'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollTo(app.staticTexts["Running, 6 mph (10 min/mile)"], in: app))
    }

    // MARK: F11 / F12 Gold gating

    func testF11_N1_basicLongerRangeOpensPaywall() {
        let app = launch("-tab", "trends")
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))
        app.buttons["30 days"].tap()
        XCTAssertTrue(app.staticTexts["Get more from every meal you log"].waitForExistence(timeout: 5))
    }

    func testF12_N1_basicPhotoLogOpensPaywall() {
        let app = launch("-tab", "diary")
        openPlus(app, pick: "Photo")
        XCTAssertTrue(app.staticTexts["Get more from every meal you log"].waitForExistence(timeout: 5))
    }

    func testF12_H1_goldPhotoLogOpens() {
        let app = launch("-gold", "-tab", "diary")
        openPlus(app, pick: "Photo")
        XCTAssertTrue(app.navigationBars["Photo log"].waitForExistence(timeout: 5))
    }

    // MARK: F10 fasting

    func testF10_H1_openFastShowsTimer() {
        let app = launch("-gold", "-sheet", "fasting")
        XCTAssertTrue(app.buttons["End fast"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["16 h fast at 20:00"].exists)
    }

    // MARK: F13 targets

    func testF13_E1_macroPercentMustSumTo100() {
        let app = launch("-tab", "more")
        forceTap(app.buttons["Energy & macro targets"])
        let protein = app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'Protein'")).firstMatch
        XCTAssertTrue(scrollTo(protein, in: app))
        protein.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()   // the "+" half of the stepper
        XCTAssertEqual(protein.value as? String, "35")
        XCTAssertTrue(scrollTo(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Adds up to 105%'")).firstMatch, in: app))
    }

    // MARK: F01 sign up / onboarding

    func testF01_N1_invalidEmailRejectedBeforeNetwork() {
        let app = launch("-phase", "signedOut")
        type("not-an-email", into: app.textFields["Email"])
        type("longenough", into: app.secureTextFields["Password"])
        app.buttons["Create account"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Enter a valid email address."].waitForExistence(timeout: 5))
    }

    func testF01_E1_onboardingNeedsWeight() {
        let app = launch("-phase", "onboarding")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Body"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].isEnabled, "weight is required")
        type("64", into: app.textFields.element(boundBy: 1))
        XCTAssertTrue(app.buttons["Continue"].isEnabled)
    }

    // MARK: accessibility

    func testA11y_diaryAudit() throws {
        let app = launch("-gold", "-tab", "diary")
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        app.activate()
        // .dynamicType is checked by screenshot at accessibility-XXXL instead: the audit also inspects the
        // unused ViewThatFits branch and reports text that is never shown truncated.
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion]) { issue in
            // System chrome (status bar, tab bar internals) isn't ours to fix.
            return issue.element?.elementType == .statusBar || issue.element?.identifier.hasPrefix("_") == true
        }
    }
}
