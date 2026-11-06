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

    /// Scrolls down, then back up, until `element` is on screen and tappable (lists load rows lazily).
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        for direction in [true, false] {
            for _ in 0..<maxSwipes {
                if element.exists && element.isHittable { return true }
                if direction { app.swipeUp() } else { app.swipeDown() }
            }
        }
        return element.exists && element.isHittable
    }

    private func openPlus(_ app: XCUIApplication, pick title: String) {
        app.buttons["Add to diary"].firstMatch.tap()
        // mince+ actions read "Photo, mince+ feature" for Basic users.
        let action = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + ",")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "plus menu should list \(title)")
        action.tap()
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Scroll the form (not the keyboard) until the field sits above the keyboard.
        let app = XCUIApplication()
        for _ in 0..<5 {
            let keyboard = app.keyboards.firstMatch
            guard keyboard.exists, field.frame.maxY > keyboard.frame.minY - 8 else { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        }
        if !field.isHittable { for _ in 0..<4 where !field.isHittable { app.swipeUp() } }
        // Tap the trailing edge so the cursor lands after existing text (number fields are right-aligned).
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    // MARK: F06 review the day

    func testF06_H1_diaryShowsGroupsEntriesAndTotals() {
        let app = launch("-plus", "-tab", "diary")
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Oats, rolled, dry"].exists)
        XCTAssertTrue(app.staticTexts["Eaten"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Breakfast'")).firstMatch.exists)   // mince+ adds "· 294 kcal"
        XCTAssertTrue(scrollTo(app.staticTexts["Vitamins"], in: app), "nutrient tables should be on the diary")
    }

    func testF06_H2_tapNutrientShowsSources() {
        let app = launch("-plus", "-tab", "diary")
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

    // MARK: F11 / F12 mince+ gating

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

    func testF12_H1_plusPhotoLogOpens() {
        let app = launch("-plus", "-tab", "diary")
        openPlus(app, pick: "Photo")
        XCTAssertTrue(app.navigationBars["Photo log"].waitForExistence(timeout: 5))
    }

    // MARK: F10 fasting

    func testF10_H1_openFastShowsTimer() {
        let app = launch("-plus", "-sheet", "fasting")
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
        let app = launch("-plus", "-tab", "diary")
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        app.activate()
        // .dynamicType is checked by screenshot at accessibility-XXXL instead: the audit also inspects the
        // unused ViewThatFits branch and reports text that is never shown truncated.
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion]) { issue in
            // System chrome (status bar, tab bar internals) isn't ours to fix.
            return issue.element?.elementType == .statusBar || issue.element?.identifier.hasPrefix("_") == true
        }
    }

    // MARK: more helpers

    private func button(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        forceTap(app.tabBars.buttons[name])
    }

    private func more(_ app: XCUIApplication, open row: String) {
        tab(app, "More")
        let item = button(app, startingWith: row)
        XCTAssertTrue(scrollTo(item, in: app), "More should list \(row)")
        item.tap()
    }

    private func assertNoErrorAlert(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.alerts["Something went wrong"].waitForExistence(timeout: 1), "unexpected error alert", file: file, line: line)
    }

    // MARK: F07 foods, recipes, meals

    func testF07_H1_createCustomFood() {
        let app = launch("-tab", "foods")
        app.buttons["Create"].tap()
        app.buttons["Custom food"].tap()
        type("Granola bar", into: app.textFields["Name"])
        type("200", into: app.textFields["Energy"])
        type("6", into: app.textFields["Protein"])
        app.buttons["Save"].tap()
        assertNoErrorAlert(app)
        XCTAssertTrue(button(app, startingWith: "Granola bar").waitForExistence(timeout: 5), "new food listed under My foods")
    }

    func testF07_E1_customFoodNeedsNameAndEnergy() {
        let app = launch("-tab", "foods")
        app.buttons["Create"].tap()
        app.buttons["Custom food"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        type("Mystery", into: app.textFields["Name"])
        XCTAssertFalse(app.buttons["Save"].isEnabled, "energy is required")
    }

    func testF07_H2_createMeal() {
        let app = launch("-tab", "foods")
        app.buttons["Create"].tap()
        app.buttons["Meal"].tap()
        type("Gym snack", into: app.textFields.firstMatch)
        app.buttons["Add ingredient"].tap()
        let almonds = button(app, startingWith: "Almonds")
        type("almond", into: app.searchFields.firstMatch)
        XCTAssertTrue(almonds.waitForExistence(timeout: 5))
        almonds.tap()
        app.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Almonds"].waitForExistence(timeout: 5), "ingredient added")
        app.buttons["Save"].tap()
        assertNoErrorAlert(app)
        app.buttons["Meals"].tap()
        XCTAssertTrue(button(app, startingWith: "Gym snack").waitForExistence(timeout: 5))
    }

    func testF07_H3_createRecipeShowsPerServingEnergy() {
        let app = launch("-tab", "foods")
        app.buttons["Create"].tap()
        app.buttons["Recipe"].tap()
        type("Rice bowl", into: app.textFields["Recipe name"])
        app.buttons["Add ingredient"].tap()
        type("rice", into: app.searchFields.firstMatch)
        let rice = button(app, startingWith: "Brown rice")
        XCTAssertTrue(rice.waitForExistence(timeout: 5))
        rice.tap()
        app.buttons["Add"].tap()                     // 1 cup = 195 g = 240 kcal
        type("2", into: app.textFields["Servings it makes"])
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '120 kcal'")).firstMatch.waitForExistence(timeout: 3),
                      "per serving = 240 / 2")
        app.buttons["Save"].tap()
        assertNoErrorAlert(app)
        app.buttons["Recipes"].tap()
        XCTAssertTrue(button(app, startingWith: "Rice bowl").waitForExistence(timeout: 5))
    }

    func testF07_E2_deleteCustomFood() {
        let app = launch("-tab", "foods")
        let bar = button(app, startingWith: "Protein bar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        bar.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(bar.waitForExistence(timeout: 2))
    }

    // MARK: F02 more diary actions

    func testF02_H2_editEntryAmount() {
        let app = launch("-tab", "diary")
        app.staticTexts["Oats, rolled, dry"].tap()
        XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
        type("2", into: app.textFields["Amount"])
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["2 × 1/2 cup · 80 g"].waitForExistence(timeout: 5))
    }

    func testF02_H3_copyThenPasteOnAnotherDay() {
        let app = launch("-tab", "diary")
        app.staticTexts["Oats, rolled, dry"].swipeRight()
        app.buttons["Copy"].firstMatch.tap()
        app.buttons["Next day"].tap()
        XCTAssertFalse(app.staticTexts["Oats, rolled, dry"].waitForExistence(timeout: 2), "tomorrow starts empty")
        app.navigationBars.buttons["More"].tap()
        app.buttons["Paste 1 item"].tap()
        XCTAssertTrue(app.staticTexts["Oats, rolled, dry"].waitForExistence(timeout: 5))
    }

    func testF02_H4_multiSelectDelete() {
        let app = launch("-tab", "diary")
        app.buttons["Select"].tap()
        app.staticTexts["Oats, rolled, dry"].tap()
        app.staticTexts["Blueberries, raw"].tap()
        app.toolbars.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["Diary"].exists, "Delete must not land on a tab")
        XCTAssertTrue(app.staticTexts["2 entries deleted"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Blueberries, raw"].exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["Blueberries, raw"].waitForExistence(timeout: 5), "undo restores both")
    }

    func testF06_H3_markDayComplete() {
        let app = launch("-tab", "diary")
        let complete = app.buttons["Mark day complete"]
        XCTAssertTrue(scrollTo(complete, in: app))
        complete.tap()
        XCTAssertTrue(app.buttons["Mark day as not complete"].waitForExistence(timeout: 5))
    }

    // MARK: F09 more quick entries

    func testF09_H3_waterAddsToTotal() {
        let app = launch("-tab", "diary")
        let water = app.descendants(matching: .any)["waterTotal"]
        XCTAssertTrue(scrollTo(water, in: app))
        let before = water.label
        openPlus(app, pick: "Water")
        XCTAssertTrue(app.navigationBars["Water"].waitForExistence(timeout: 5))
        sleep(1)   // let the sheet finish presenting
        app.buttons["500 mL"].tap()
        XCTAssertTrue(app.navigationBars["Water"].waitForNonExistence(timeout: 5), "sheet closes after adding")
        XCTAssertTrue(scrollTo(water, in: app))
        XCTAssertNotEqual(water.label, before)
        XCTAssertTrue(scrollTo(app.staticTexts["500 mL"], in: app), "the log shows as water, not as a 0 kcal food")
    }

    func testF09_H4_note() {
        let app = launch("-tab", "diary")
        openPlus(app, pick: "Note")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Slept badly")
        app.buttons["Save"].tap()
        XCTAssertTrue(scrollTo(app.staticTexts["Slept badly"], in: app))
    }

    func testF09_H5_weight() {
        let app = launch("-tab", "diary")
        openPlus(app, pick: "Weight")
        type("63.5", into: app.textFields["Weight"])
        app.buttons["Save"].tap()
        XCTAssertTrue(scrollTo(app.staticTexts["63.5 kg"], in: app))
    }

    // MARK: F10 / F13 / F14 mince+ flows

    func testF10_H2_endAndStartFast() {
        let app = launch("-plus", "-sheet", "fasting")
        app.buttons["End fast"].tap()
        let start = app.buttons["Start fast"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.buttons["End fast"].waitForExistence(timeout: 5))
        assertNoErrorAlert(app)
    }

    func testF14_H1_repeatAnEntry() {
        let app = launch("-plus", "-tab", "diary")
        app.staticTexts["Blueberries, raw"].press(forDuration: 1.2)
        app.buttons["Repeat"].tap()
        app.buttons["Save"].tap()
        assertNoErrorAlert(app)
        more(app, open: "Repeat items")
        XCTAssertTrue(app.staticTexts["Blueberries, raw"].waitForExistence(timeout: 5))
    }

    func testF13_H2_macroSchedulerTemplate() {
        let app = launch("-plus", "-tab", "more")
        more(app, open: "Macro Scheduler")
        app.buttons["New template"].tap()
        type("Rest day", into: app.textFields["Name (e.g. Training day)"])
        type("1800", into: app.textFields["Energy"])
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Rest day"].waitForExistence(timeout: 5))
    }

    func testF13_H3_nutrientOverride() {
        let app = launch("-tab", "more")
        more(app, open: "Vitamin & mineral targets")
        let iron = button(app, startingWith: "Iron")
        XCTAssertTrue(scrollTo(iron, in: app))
        iron.tap()
        type("12", into: app.textFields["At least"])
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["custom"].waitForExistence(timeout: 5))
    }

    func testF11_H1_plusLongerRange() {
        let app = launch("-plus", "-tab", "trends")
        app.buttons["30 days"].tap()
        XCTAssertFalse(app.staticTexts["Get more from every meal you log"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'of 30'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testF11_H2_customChart() {
        let app = launch("-plus", "-tab", "trends")
        let link = button(app, startingWith: "Custom charts")
        XCTAssertTrue(scrollTo(link, in: app))
        link.tap()
        app.buttons["New chart"].tap()
        type("Fiber trend", into: app.textFields["Title"])
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Fiber trend"].waitForExistence(timeout: 5))
    }

    // MARK: F16 data, groups

    func testF16_H1_bulkDeleteClearsDiary() {
        let app = launch("-tab", "more")
        more(app, open: "Export & delete")
        app.buttons["Delete diary entries in this range"].tap()
        app.buttons["Delete entries"].tap()
        tab(app, "Diary")
        XCTAssertTrue(app.navigationBars["Diary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Oats, rolled, dry"].waitForExistence(timeout: 2))
    }

    func testF02_E3_addDiaryGroup() {
        let app = launch("-tab", "more")
        more(app, open: "Diary groups")
        type("Pre-workout", into: app.textFields["New group"])
        app.buttons["Add"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back saves
        tab(app, "Diary")
        XCTAssertTrue(scrollTo(app.staticTexts["Pre-workout"], in: app))
    }

    // MARK: smoke: every settings screen opens

    func testSmoke_everyMoreScreenOpens() {
        let app = launch("-plus", "-tab", "more")
        let rows = ["Profile & body": "Profile", "Energy & macro targets": "Targets", "Vitamin & mineral targets": "Nutrient targets",
                    "Macro Scheduler": "Macro Scheduler", "Diary groups": "Diary groups", "Repeat items": "Repeat items",
                    "Customise the + menu": "+ menu", "Progress photos": "Progress photos", "Apple Health": "Apple Health",
                    "Export & delete": "Data", "About & data sources": "About"]
        for (row, title) in rows {
            let item = button(app, startingWith: row)
            XCTAssertTrue(scrollTo(item, in: app), row)
            item.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(row) -> \(title)")
            assertNoErrorAlert(app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 5))
        }
    }

    func testSmoke_everyTabLoadsWithoutErrors() {
        let app = launch("-plus", "-tab", "dashboard")
        for (name, title) in [("Dashboard", "Today"), ("Diary", "Diary"), ("Trends", "Trends"), ("Foods", "Foods"), ("More", "More")] {
            tab(app, name)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), name)
            assertNoErrorAlert(app)
        }
    }
}
