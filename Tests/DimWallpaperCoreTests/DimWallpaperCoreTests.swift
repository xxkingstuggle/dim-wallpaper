import Foundation
import XCTest
@testable import DimWallpaperCore

final class DimWallpaperCoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "local.zjx.DimWallpaper.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
    }

    func testIntensityClampingAndPercentageGuardAgainstExtremeAndNonFiniteValues() {
        XCTAssertEqual(DimmingBounds.clampedIntensity(-0.5), DimmingBounds.minimumIntensity)
        XCTAssertEqual(DimmingBounds.clampedIntensity(0.0), DimmingBounds.minimumIntensity)
        XCTAssertEqual(DimmingBounds.clampedIntensity(0.42), 0.42, accuracy: 0.0001)
        XCTAssertEqual(DimmingBounds.clampedIntensity(1.5), DimmingBounds.maximumIntensity)
        XCTAssertEqual(DimmingBounds.clampedIntensity(.nan), DimmingBounds.defaultIntensity)
        XCTAssertEqual(DimmingBounds.clampedIntensity(.infinity), DimmingBounds.defaultIntensity)
        XCTAssertEqual(DimmingBounds.clampedIntensity(-.infinity), DimmingBounds.defaultIntensity)

        XCTAssertEqual(DimmingBounds.percentage(for: 0.25), 25)
        XCTAssertEqual(DimmingBounds.percentage(for: 0.99), 80)
        XCTAssertEqual(DimmingBounds.percentage(for: .nan), 40)
    }

    func testPresetMatchingRespectsToleranceAndValues() {
        XCTAssertEqual(DimmingPreset.matching(intensity: 0.25), .gentle)
        XCTAssertEqual(DimmingPreset.matching(intensity: 0.455), .focus)
        XCTAssertEqual(DimmingPreset.matching(intensity: 0.65), .night)
        XCTAssertEqual(DimmingPreset.matching(intensity: 0.80), .deep)
        XCTAssertNil(DimmingPreset.matching(intensity: 0.35))
    }

    func testWindowLevelPolicyPlacesOverlayStrictlyAboveDesktopAndBelowIcons() {
        let desktop: Int32 = -2_147_483_623
        let icons: Int32 = -2_147_483_603
        let resolved = OverlayWindowPolicy.resolvedWindowLevel(desktopLevel: desktop, desktopIconLevel: icons)
        XCTAssertEqual(resolved, Int(desktop) + 1)
        XCTAssertTrue(OverlayWindowPolicy.isStrictlyBetweenDesktopAndIcons(level: resolved, desktopLevel: desktop, desktopIconLevel: icons))

        let degenerate = OverlayWindowPolicy.resolvedWindowLevel(desktopLevel: 10, desktopIconLevel: 11)
        XCTAssertEqual(degenerate, 10)
        XCTAssertFalse(OverlayWindowPolicy.isStrictlyBetweenDesktopAndIcons(level: degenerate, desktopLevel: 10, desktopIconLevel: 11))
    }

    func testEngineStateMatrixAcrossAppearanceDarkOnlyAndMultiDisplayExclusion() {
        let mainDisplay = DisplayDescriptor(
            id: 101,
            name: "Built-in Retina Display",
            logicalWidth: 1512,
            logicalHeight: 982,
            scaleFactor: 2.0,
            isBuiltIn: true,
            isMain: true
        )
        let externalDisplay = DisplayDescriptor(
            id: 202,
            name: "Studio Display",
            logicalWidth: 2560,
            logicalHeight: 1440,
            scaleFactor: 2.0,
            isBuiltIn: false,
            isMain: false
        )
        XCTAssertEqual(mainDisplay.resolutionLabel, "1512×982 · 2x")

        var engine = DimmingEngineState(
            snapshot: DimmingSnapshot(enabled: true, intensity: 0.45, darkOnly: true),
            isDarkAppearance: false,
            displays: [mainDisplay, externalDisplay]
        )
        XCTAssertFalse(engine.isGloballyActive)
        XCTAssertEqual(engine.statusSymbolName, "sun.max")
        XCTAssertEqual(engine.statusBadgeTitle, "浅色待命")
        XCTAssertFalse(engine.decision(for: 101).shouldShowWindow)

        engine.isDarkAppearance = true
        XCTAssertTrue(engine.isGloballyActive)
        XCTAssertEqual(engine.activeDisplayCount, 2)
        XCTAssertEqual(engine.statusSymbolName, "moon.fill")
        XCTAssertEqual(engine.decision(for: 101).targetAlpha, 0.45, accuracy: 0.0001)
        XCTAssertEqual(engine.decision(for: 202).targetAlpha, 0.45, accuracy: 0.0001)

        engine.setDisplayExcluded(202, excluded: true)
        XCTAssertEqual(engine.activeDisplayCount, 1)
        XCTAssertTrue(engine.decision(for: 101).shouldShowWindow)
        XCTAssertFalse(engine.decision(for: 202).shouldShowWindow)
        XCTAssertTrue(engine.statusSummary.contains("1/2 屏"))

        engine.setDisplayExcluded(101, excluded: true)
        XCTAssertEqual(engine.activeDisplayCount, 0)
        XCTAssertFalse(engine.isDimmingAnyDisplay)
        XCTAssertEqual(engine.statusBadgeTitle, "全部豁免")
        XCTAssertEqual(engine.effectivePreviewAlpha, 0)

        engine.setDisplayExcluded(101, excluded: false)
        engine.setEnabled(false)
        XCTAssertEqual(engine.statusSymbolName, "circle.slash")
        XCTAssertEqual(engine.statusBadgeTitle, "已暂停")
        XCTAssertFalse(engine.decision(for: 101).shouldShowWindow)

        engine.updateDisplays([mainDisplay])
        XCTAssertEqual(engine.staleDisplayIDs(existingWindowIDs: [101, 202, 303]), [202, 303])
    }

    func testHotKeyBindingValidationAndCanonicalDisplayLabel() {
        XCTAssertTrue(HotKeyBinding.defaultToggle.isValid)
        XCTAssertEqual(HotKeyBinding.defaultToggle.displayLabel, "⌥⌘D")

        let fullModifiers = HotKeyBinding(
            keyCode: 2,
            modifiers: HotKeyBinding.controlMask | HotKeyBinding.optionMask | HotKeyBinding.shiftMask | HotKeyBinding.commandMask
        )
        XCTAssertTrue(fullModifiers.isValid)
        XCTAssertEqual(fullModifiers.displayLabel, "⌃⌥⇧⌘D")

        let noModifier = HotKeyBinding(keyCode: 2, modifiers: 0)
        XCTAssertFalse(noModifier.isValid)

        let shiftOnly = HotKeyBinding(keyCode: 2, modifiers: HotKeyBinding.shiftMask)
        XCTAssertFalse(shiftOnly.isValid)

        let invalidKeyCode = HotKeyBinding(keyCode: 200, modifiers: HotKeyBinding.commandMask)
        XCTAssertFalse(invalidKeyCode.isValid)
    }

    func testPreferencesStoreIsolatedSuiteRoundTripAndMalformedValueSanitization() {
        let store = PreferencesStore(userDefaults: defaults, suiteName: suiteName)
        let initial = store.load()
        XCTAssertTrue(initial.enabled)
        XCTAssertEqual(initial.intensity, 0.40, accuracy: 0.0001)
        XCTAssertTrue(initial.darkOnly)
        XCTAssertEqual(initial.tint, .neutral)
        XCTAssertTrue(initial.excludedDisplayIDs.isEmpty)
        XCTAssertTrue(initial.hotKeyEnabled)
        XCTAssertEqual(initial.hotKeyBinding, .defaultToggle)

        let custom = DimmingSnapshot(
            enabled: false,
            intensity: 0.65,
            darkOnly: false,
            tint: .warmNight,
            excludedDisplayIDs: [101, 404],
            hotKeyEnabled: false,
            hotKeyBinding: HotKeyBinding(keyCode: 14, modifiers: HotKeyBinding.controlMask | HotKeyBinding.optionMask)
        )
        store.save(custom)

        let reloaded = store.load()
        XCTAssertEqual(reloaded, custom)

        defaults.set(9.5, forKey: PreferenceKey.intensity)
        defaults.set("unknown-tint", forKey: PreferenceKey.tint)
        defaults.set(0, forKey: PreferenceKey.hotKeyModifiers)
        let sanitized = store.load()
        XCTAssertEqual(sanitized.intensity, DimmingBounds.maximumIntensity)
        XCTAssertEqual(sanitized.tint, .neutral)
        XCTAssertEqual(sanitized.hotKeyBinding, .defaultToggle)
    }

    func testLaunchOptionsParsingAndDiagnosticReportSerialization() throws {
        let parsed = LaunchOptions.parse(
            arguments: ["DimWallpaper", "--status-json", "--defaults-suite", "sandbox.suite", "--allow-multiple-instances"],
            environment: [:]
        )
        XCTAssertFalse(parsed.printStatus)
        XCTAssertTrue(parsed.printStatusJSON)
        XCTAssertEqual(parsed.defaultsSuiteName, "sandbox.suite")
        XCTAssertTrue(parsed.disableLoginItemSetup)
        XCTAssertTrue(parsed.allowMultipleInstances)

        let fromEnv = LaunchOptions.parse(
            arguments: ["DimWallpaper", "--status"],
            environment: [LaunchOptions.defaultsSuiteEnvironmentKey: "env.suite"]
        )
        XCTAssertTrue(fromEnv.printStatus)
        XCTAssertEqual(fromEnv.defaultsSuiteName, "env.suite")
        XCTAssertTrue(fromEnv.disableLoginItemSetup)

        let display = DisplayDescriptor(
            id: 1,
            name: "Main",
            logicalWidth: 1920,
            logicalHeight: 1080,
            scaleFactor: 1.5,
            isBuiltIn: false,
            isMain: true
        )
        XCTAssertEqual(display.resolutionLabel, "1920×1080 · 1.5x")

        let report = DiagnosticReport(
            version: "1.1.0",
            suiteName: "sandbox.suite",
            snapshot: DimmingSnapshot(enabled: true, intensity: 0.45, darkOnly: true, tint: .coolSlate, excludedDisplayIDs: [2]),
            displays: [display],
            loginItemStatus: 0
        )
        XCTAssertTrue(report.legacyLine().contains("enabled=true intensity=0.45 darkOnly=true tint=coolSlate"))
        let jsonText = try report.jsonString()
        let decoded = try JSONDecoder().decode(DiagnosticReport.self, from: Data(jsonText.utf8))
        XCTAssertEqual(decoded, report)
    }
}
