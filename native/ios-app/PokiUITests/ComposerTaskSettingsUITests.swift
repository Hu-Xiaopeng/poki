import XCTest

final class ComposerTaskSettingsUITests: XCTestCase {
    func testShortcutsExpandAndReturnToDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-pokiChat", "empty", "-pokiDraft", "Draft for Poki", "-pokiComposerModelPreview",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        let editor = app.textViews["capsule.field"]
        let plus = app.buttons["composer.plus"]
        let approval = app.buttons["composer.settings.approval"]
        let model = app.buttons["composer.settings.model"]
        let close = app.buttons["composer.settings.close"]
        let addModel = app.buttons["composer.model.setup"]
        let chatGPT = app.buttons["composer.model.chatgpt.gpt-6.1-terra"]
        let deepSeek = app.buttons["composer.model.deepseek.deepseek-flash"]
        let deepSeekPro = app.buttons["composer.model.deepseek.deepseek-v4-pro"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        let compactOffset = plus.frame.midY - editor.frame.midY

        editor.tap()
        XCTAssertTrue(approval.waitForExistence(timeout: 5))
        XCTAssertTrue(approval.isHittable)
        XCTAssertTrue(model.isHittable)
        XCTAssertGreaterThan(plus.frame.midY - editor.frame.midY, compactOffset + 20)
        XCTAssertLessThan(approval.frame.midX, model.frame.midX)
        XCTAssertEqual(approval.frame.midY, model.frame.midY, accuracy: 2)
        XCTAssertEqual(editor.value as? String, "Draft for Poki")

        let modes = ["reply", "confirm", "off"]
        approval.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let options = modes.map { app.buttons["composer.approval.\($0)"] }
        let originallySelected = options.first { $0.isSelected }
        XCTAssertNotNil(originallySelected)
        for option in options {
            XCTAssertTrue(option.isHittable)
            option.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            approval.tap()
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            XCTAssertTrue(option.isSelected)
        }
        originallySelected?.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(approval.isHittable)
        XCTAssertEqual(editor.value as? String, "Draft for Poki")

        model.tap()
        XCTAssertTrue(chatGPT.waitForExistence(timeout: 5))
        XCTAssertTrue(chatGPT.isSelected)
        for option in [deepSeek, deepSeekPro] {
            if !option.isHittable { app.swipeUp() }
            XCTAssertTrue(option.isHittable)
            option.tap()
            XCTAssertTrue(option.isSelected)
        }
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertTrue(model.isHittable)
        XCTAssertEqual(editor.value as? String, "Draft for Poki")
        editor.typeText(".")
        XCTAssertEqual((editor.value as? String)?.replacingOccurrences(of: ".", with: ""), "Draft for Poki")
        XCTAssertTrue((editor.value as? String)?.contains(".") == true)

        model.tap()
        XCTAssertTrue(deepSeekPro.waitForExistence(timeout: 5))
        if !deepSeekPro.isHittable { app.swipeUp() }
        XCTAssertTrue(deepSeekPro.isSelected)
        if !addModel.isHittable { app.swipeUp() }
        addModel.tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["Models", "模型"])).firstMatch.waitForExistence(timeout: 5))
    }
}
