import CoreGraphics
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
        XCTAssertEqual(HotKeyBinding.defaultToggle.displayLabel, "⌃⌥⌘D")
        XCTAssertTrue(HotKeyBinding.defaultFocusToggle.isValid)
        XCTAssertEqual(HotKeyBinding.defaultFocusToggle.displayLabel, "⌃⌥⌘F")
        XCTAssertNotEqual(HotKeyBinding.defaultToggle, HotKeyBinding.defaultFocusToggle)

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

    func testFocusBoundsPresetsAndTransitionDurationRespectReduceMotion() {
        XCTAssertEqual(FocusBounds.clampedIntensity(-0.2), FocusBounds.minimumIntensity)
        XCTAssertEqual(FocusBounds.clampedIntensity(0.45), 0.45, accuracy: 0.0001)
        XCTAssertEqual(FocusBounds.clampedIntensity(2.5), FocusBounds.maximumIntensity)
        XCTAssertEqual(FocusBounds.clampedIntensity(.nan), FocusBounds.defaultIntensity)
        XCTAssertEqual(FocusBounds.clampedIntensity(.infinity), FocusBounds.defaultIntensity)

        XCTAssertEqual(FocusPreset.matching(intensity: 0.25), .soft)
        XCTAssertEqual(FocusPreset.matching(intensity: 0.45), .balanced)
        XCTAssertEqual(FocusPreset.matching(intensity: 0.65), .cinema)
        XCTAssertEqual(FocusPreset.matching(intensity: 0.85), .deep)
        XCTAssertNil(FocusPreset.matching(intensity: 0.55))

        XCTAssertEqual(FocusTransitionSpeed.gentle.resolvedDuration(reduceMotion: false), 0.18, accuracy: 0.0001)
        XCTAssertEqual(FocusTransitionSpeed.snappy.resolvedDuration(reduceMotion: false), 0.08, accuracy: 0.0001)
        XCTAssertEqual(FocusTransitionSpeed.instant.resolvedDuration(reduceMotion: false), 0.0, accuracy: 0.0001)
        XCTAssertEqual(FocusTransitionSpeed.gentle.resolvedDuration(reduceMotion: true), 0.0, accuracy: 0.0001)
        XCTAssertEqual(FocusTransitionSpeed.snappy.resolvedDuration(reduceMotion: true), 0.0, accuracy: 0.0001)

        XCTAssertEqual(FocusSystemBarPreset.matching(dimMenuBar: false, dimDock: false), .keepSystemBars)
        XCTAssertEqual(FocusSystemBarPreset.matching(dimMenuBar: true, dimDock: true), .dimAll)
        XCTAssertNil(FocusSystemBarPreset.matching(dimMenuBar: true, dimDock: false))
        XCTAssertNil(FocusSystemBarPreset.matching(dimMenuBar: false, dimDock: true))
    }

    func testDualDisplayCGToAppKitCoordinateConversion() {
        let primaryHeight = 1080.0

        let primaryTopWindow = FocusCoordinateSpace.cgRectToAppKitRect(
            CGRect(x: 120, y: 40, width: 900, height: 600),
            primaryScreenHeight: primaryHeight
        )
        XCTAssertEqual(primaryTopWindow, CGRect(x: 120, y: 440, width: 900, height: 600))

        let rightSecondaryWindow = FocusCoordinateSpace.cgRectToAppKitRect(
            CGRect(x: 1960, y: 164, width: 1200, height: 780),
            primaryScreenHeight: primaryHeight
        )
        XCTAssertEqual(rightSecondaryWindow, CGRect(x: 1960, y: 136, width: 1200, height: 780))

        let stackedAboveSecondaryWindow = FocusCoordinateSpace.cgRectToAppKitRect(
            CGRect(x: 200, y: -956, width: 1000, height: 500),
            primaryScreenHeight: primaryHeight
        )
        XCTAssertEqual(stackedAboveSecondaryWindow, CGRect(x: 200, y: 1536, width: 1000, height: 500))

        let stackedBelowSecondaryWindow = FocusCoordinateSpace.cgRectToAppKitRect(
            CGRect(x: -1470, y: 1120, width: 800, height: 600),
            primaryScreenHeight: primaryHeight
        )
        XCTAssertEqual(stackedBelowSecondaryWindow, CGRect(x: -1470, y: -640, width: 800, height: 600))
    }

    func testFocusWindowLevelsStayWithinSafeBounds() {
        let menuLevel = FocusWindowLevels.menuBarOverlayLevel(statusBarLevel: 25, popUpMenuLevel: 101)
        XCTAssertEqual(menuLevel, 26)
        XCTAssertGreaterThan(menuLevel, 25)
        XCTAssertLessThan(menuLevel, 101)

        let dockLevel = FocusWindowLevels.dockOverlayLevel(dockLevel: 20, mainMenuLevel: 24)
        XCTAssertEqual(dockLevel, 21)
        XCTAssertGreaterThan(dockLevel, 20)
        XCTAssertLessThan(dockLevel, 24)

        let tightMenu = FocusWindowLevels.menuBarOverlayLevel(statusBarLevel: 25, popUpMenuLevel: 26)
        XCTAssertEqual(tightMenu, 25)
    }

    func testFocusScreenPartitionZeroOverlapAcrossMenuBarAllDockEdgesAndForegroundOverhang() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let noBars = FocusScreenPartition.partition(
            screenFrame: screen,
            visibleFrame: CGRect(x: 0, y: 72, width: 1920, height: 983),
            dimMenuBar: false,
            dimDock: false,
            foregroundWindowFrames: []
        )
        XCTAssertEqual(noBars.mainRect, screen)
        XCTAssertNil(noBars.menuBarStripRect)
        XCTAssertTrue(noBars.dockStripRects.isEmpty)
        assertPartitionDisjoint(noBars.allRects, expectedTotalArea: screen.width * screen.height, inside: screen)

        let bottomDockVisible = CGRect(x: 0, y: 72, width: 1920, height: 983)
        let bottomPartition = FocusScreenPartition.partition(
            screenFrame: screen,
            visibleFrame: bottomDockVisible,
            dimMenuBar: true,
            dimDock: true,
            foregroundWindowFrames: []
        )
        XCTAssertEqual(bottomPartition.menuBarStripRect, CGRect(x: 0, y: 1055, width: 1920, height: 25))
        XCTAssertEqual(bottomPartition.dockStripRects, [CGRect(x: 0, y: 0, width: 1920, height: 72)])
        XCTAssertEqual(bottomPartition.mainRect, CGRect(x: 0, y: 72, width: 1920, height: 983))
        assertPartitionDisjoint(bottomPartition.allRects, expectedTotalArea: screen.width * screen.height, inside: screen)

        let leftDockVisible = CGRect(x: 68, y: 0, width: 1852, height: 1055)
        let leftPartition = FocusScreenPartition.partition(
            screenFrame: screen,
            visibleFrame: leftDockVisible,
            dimMenuBar: true,
            dimDock: true,
            foregroundWindowFrames: []
        )
        XCTAssertEqual(leftPartition.menuBarStripRect, CGRect(x: 0, y: 1055, width: 1920, height: 25))
        XCTAssertEqual(leftPartition.dockStripRects, [CGRect(x: 0, y: 0, width: 68, height: 1055)])
        XCTAssertEqual(leftPartition.mainRect, CGRect(x: 68, y: 0, width: 1852, height: 1055))
        assertPartitionDisjoint(leftPartition.allRects, expectedTotalArea: screen.width * screen.height, inside: screen)

        let rightDockVisible = CGRect(x: 0, y: 0, width: 1856, height: 1055)
        let rightPartition = FocusScreenPartition.partition(
            screenFrame: screen,
            visibleFrame: rightDockVisible,
            dimMenuBar: true,
            dimDock: true,
            foregroundWindowFrames: []
        )
        XCTAssertEqual(rightPartition.menuBarStripRect, CGRect(x: 0, y: 1055, width: 1920, height: 25))
        XCTAssertEqual(rightPartition.dockStripRects, [CGRect(x: 1856, y: 0, width: 64, height: 1055)])
        XCTAssertEqual(rightPartition.mainRect, CGRect(x: 0, y: 0, width: 1856, height: 1055))
        assertPartitionDisjoint(rightPartition.allRects, expectedTotalArea: screen.width * screen.height, inside: screen)

        let overhangWindow = CGRect(x: 500, y: 20, width: 700, height: 800)
        let overhangingPartition = FocusScreenPartition.partition(
            screenFrame: screen,
            visibleFrame: bottomDockVisible,
            dimMenuBar: true,
            dimDock: true,
            foregroundWindowFrames: [overhangWindow]
        )
        let dockRect = CGRect(x: 0, y: 0, width: 1920, height: 72)
        let cutoutOverlap = dockRect.intersection(overhangWindow)
        let expectedArea = screen.width * screen.height - cutoutOverlap.width * cutoutOverlap.height
        assertPartitionDisjoint(overhangingPartition.allRects, expectedTotalArea: expectedArea, inside: screen)
        for strip in overhangingPartition.dockStripRects {
            let hit = strip.intersection(overhangWindow)
            XCTAssertTrue(hit.isNull || hit.isEmpty || hit.width * hit.height < 0.01)
        }

        let fullCoverDockWindow = CGRect(x: -50, y: -20, width: 2020, height: 900)
        let coveredDockPartition = FocusScreenPartition.partition(
            screenFrame: screen,
            visibleFrame: bottomDockVisible,
            dimMenuBar: true,
            dimDock: true,
            foregroundWindowFrames: [fullCoverDockWindow]
        )
        XCTAssertTrue(coveredDockPartition.dockStripRects.isEmpty)
        XCTAssertEqual(coveredDockPartition.mainRect, bottomDockVisible)

        let fullScreenSpace = FocusScreenPartition.partition(
            screenFrame: screen,
            visibleFrame: screen,
            dimMenuBar: true,
            dimDock: true,
            foregroundWindowFrames: []
        )
        XCTAssertNil(fullScreenSpace.menuBarStripRect)
        XCTAssertTrue(fullScreenSpace.dockStripRects.isEmpty)
        XCTAssertEqual(fullScreenSpace.mainRect, screen)
    }

    func testFocusWindowOrderPlannerContiguousGroupSandwichedWindowsAndMultiDisplayPolicies() {
        let primaryScreen = ScreenGeometry(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 72, width: 1920, height: 983),
            isPrimary: true
        )
        let secondaryScreen = ScreenGeometry(
            displayID: 2,
            frame: CGRect(x: 1920, y: 0, width: 1470, height: 956),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1470, height: 931),
            isPrimary: false
        )
        let screens = [primaryScreen, secondaryScreen]
        let targetPID: Int32 = 500
        let otherPID: Int32 = 600
        let selfPID: Int32 = 999

        let windows: [ObservedWindowInfo] = [
            ObservedWindowInfo(windowNumber: 900, ownerPID: selfPID, layer: 0, alpha: 0.45, cgBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            ObservedWindowInfo(windowNumber: 901, ownerPID: otherPID, layer: 25, alpha: 1.0, cgBounds: CGRect(x: 0, y: 0, width: 1920, height: 25)),
            ObservedWindowInfo(windowNumber: 902, ownerPID: otherPID, layer: 0, alpha: 1.0, cgBounds: CGRect(x: 10, y: 10, width: 20, height: 20)),
            ObservedWindowInfo(windowNumber: 101, ownerPID: targetPID, layer: 0, alpha: 1.0, cgBounds: CGRect(x: 100, y: 100, width: 800, height: 600)),
            ObservedWindowInfo(windowNumber: 102, ownerPID: targetPID, layer: 0, alpha: 1.0, cgBounds: CGRect(x: 920, y: 120, width: 700, height: 550)),
            ObservedWindowInfo(windowNumber: 201, ownerPID: otherPID, layer: 0, alpha: 1.0, cgBounds: CGRect(x: 200, y: 200, width: 900, height: 600)),
            ObservedWindowInfo(windowNumber: 103, ownerPID: targetPID, layer: 0, alpha: 1.0, cgBounds: CGRect(x: 300, y: 240, width: 640, height: 480)),
            ObservedWindowInfo(windowNumber: 301, ownerPID: otherPID, layer: 0, alpha: 1.0, cgBounds: CGRect(x: 2000, y: 200, width: 1000, height: 700)),
            ObservedWindowInfo(windowNumber: 104, ownerPID: targetPID, layer: 0, alpha: 1.0, cgBounds: CGRect(x: 2060, y: 240, width: 900, height: 640)),
        ]

        let frontAppDimInactive = FocusWindowOrderPlanner.plan(
            screens: screens,
            windows: windows,
            targetPID: targetPID,
            selfPID: selfPID,
            isEnabled: true,
            intensity: 0.50,
            scope: .frontApplication,
            dimMenuBar: true,
            dimDock: true,
            multiDisplayPolicy: .dimInactiveScreens
        )
        XCTAssertEqual(frontAppDimInactive.count, 2)
        XCTAssertEqual(frontAppDimInactive[0].placement, .orderBelow(windowNumber: 102))
        XCTAssertEqual(frontAppDimInactive[0].foregroundWindowFrames.count, 2)
        XCTAssertEqual(frontAppDimInactive[0].targetAlpha, 0.50, accuracy: 0.0001)
        XCTAssertEqual(frontAppDimInactive[1].placement, .orderFrontNormal)
        XCTAssertTrue(frontAppDimInactive[1].foregroundWindowFrames.isEmpty)
        XCTAssertEqual(frontAppDimInactive[1].targetAlpha, 0.50, accuracy: 0.0001)

        let frontWindowActiveOnly = FocusWindowOrderPlanner.plan(
            screens: screens,
            windows: windows,
            targetPID: targetPID,
            selfPID: selfPID,
            isEnabled: true,
            intensity: 0.50,
            scope: .frontWindow,
            dimMenuBar: false,
            dimDock: false,
            multiDisplayPolicy: .activeScreenOnly
        )
        XCTAssertEqual(frontWindowActiveOnly[0].placement, .orderBelow(windowNumber: 101))
        XCTAssertEqual(frontWindowActiveOnly[0].foregroundWindowFrames.count, 1)
        XCTAssertEqual(frontWindowActiveOnly[1].placement, .hidden)
        XCTAssertEqual(frontWindowActiveOnly[1].targetAlpha, 0.0)
        XCTAssertFalse(frontWindowActiveOnly[1].shouldShow)

        let disabledPlans = FocusWindowOrderPlanner.plan(
            screens: screens,
            windows: windows,
            targetPID: targetPID,
            selfPID: selfPID,
            isEnabled: false,
            intensity: 0.50,
            scope: .frontApplication,
            dimMenuBar: true,
            dimDock: true,
            multiDisplayPolicy: .dimInactiveScreens
        )
        XCTAssertTrue(disabledPlans.allSatisfy { $0.placement == .hidden && $0.targetAlpha == 0.0 })

        let excludedSecondaryPlans = FocusWindowOrderPlanner.plan(
            screens: screens,
            windows: windows,
            targetPID: targetPID,
            selfPID: selfPID,
            isEnabled: true,
            intensity: 0.50,
            scope: .frontApplication,
            dimMenuBar: true,
            dimDock: true,
            multiDisplayPolicy: .dimInactiveScreens,
            excludedDisplayIDs: [2]
        )
        XCTAssertEqual(excludedSecondaryPlans[0].placement, .orderBelow(windowNumber: 102))
        XCTAssertEqual(excludedSecondaryPlans[0].targetAlpha, 0.50, accuracy: 0.0001)
        XCTAssertEqual(excludedSecondaryPlans[1].placement, .hidden)
        XCTAssertEqual(excludedSecondaryPlans[1].targetAlpha, 0.0)
        XCTAssertNil(excludedSecondaryPlans[1].partition.menuBarStripRect)
        XCTAssertTrue(excludedSecondaryPlans[1].partition.dockStripRects.isEmpty)
        XCTAssertFalse(excludedSecondaryPlans[1].shouldShow)
    }

    func testFocusTargetResolverSelfKeepAliveTransientAppsAndExclusionToggle() {
        let selfPID: Int32 = 888
        var resolver = FocusTargetResolver(selfPID: selfPID)
        let selfApp = FocusAppIdentity(pid: selfPID, bundleIdentifier: "local.zjx.DimWallpaper", localizedName: "DimWallpaper")
        let safari = FocusAppIdentity(pid: 201, bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
        let spotlight = FocusAppIdentity(pid: 202, bundleIdentifier: "com.apple.Spotlight", localizedName: "Spotlight")
        let controlCenter = FocusAppIdentity(pid: 203, bundleIdentifier: "com.apple.controlcenter", localizedName: "Control Center")
        let xcode = FocusAppIdentity(pid: 204, bundleIdentifier: "com.apple.dt.Xcode", localizedName: "Xcode")

        XCTAssertEqual(resolver.resolve(currentFrontmost: selfApp, excludedBundleIDs: []), .unavailable)
        XCTAssertNil(resolver.lastExternalFrontmostApp)

        XCTAssertEqual(resolver.resolve(currentFrontmost: safari, excludedBundleIDs: []), .active(safari))
        XCTAssertEqual(resolver.lastExternalFrontmostApp, safari)

        XCTAssertEqual(resolver.resolve(currentFrontmost: selfApp, excludedBundleIDs: []), .active(safari))
        XCTAssertEqual(resolver.resolve(currentFrontmost: spotlight, excludedBundleIDs: []), .active(safari))
        XCTAssertEqual(resolver.resolve(currentFrontmost: controlCenter, excludedBundleIDs: []), .active(safari))
        XCTAssertEqual(resolver.lastExternalFrontmostApp, safari)

        let excluded: Set<String> = ["com.apple.dt.Xcode"]
        XCTAssertEqual(resolver.resolve(currentFrontmost: xcode, excludedBundleIDs: excluded), .pausedByExcludedApp(xcode))
        XCTAssertEqual(resolver.lastExternalFrontmostApp, xcode)
        XCTAssertEqual(resolver.resolve(currentFrontmost: selfApp, excludedBundleIDs: excluded), .pausedByExcludedApp(xcode))
        XCTAssertEqual(resolver.resolve(currentFrontmost: selfApp, excludedBundleIDs: []), .active(xcode))
    }

    func testFocusTargetResolverIgnoresNonRegularHelpersAndFallsBackToTopStandardWindowOnColdStart() {
        let selfPID: Int32 = 888
        let chatGPTPID: Int32 = 410
        let notificationPID: Int32 = 420
        let helperPID: Int32 = 430

        let chatGPT = FocusAppIdentity(
            pid: chatGPTPID,
            bundleIdentifier: "com.openai.chat",
            localizedName: "ChatGPT",
            isRegularActivationPolicy: true
        )
        let userNotificationCenter = FocusAppIdentity(
            pid: notificationPID,
            bundleIdentifier: "com.apple.UserNotificationCenter",
            localizedName: "UserNotificationCenter",
            isRegularActivationPolicy: false
        )
        let menuBarHelper = FocusAppIdentity(
            pid: helperPID,
            bundleIdentifier: "com.example.MenuBarHelper",
            localizedName: "MenuBarHelper",
            isRegularActivationPolicy: false
        )
        let selfApp = FocusAppIdentity(
            pid: selfPID,
            bundleIdentifier: "local.zjx.DimWallpaper",
            localizedName: "DimWallpaper",
            isRegularActivationPolicy: false
        )

        let observedWindows: [ObservedWindowInfo] = [
            ObservedWindowInfo(windowNumber: 10, ownerPID: notificationPID, layer: 8, alpha: 1.0, cgBounds: CGRect(x: 800, y: 80, width: 360, height: 120)),
            ObservedWindowInfo(windowNumber: 11, ownerPID: selfPID, layer: 0, alpha: 0.45, cgBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            ObservedWindowInfo(windowNumber: 12, ownerPID: chatGPTPID, layer: 0, alpha: 1.0, cgBounds: CGRect(x: 120, y: 80, width: 1200, height: 820)),
        ]
        let appsByPID: [Int32: FocusAppIdentity] = [
            chatGPTPID: chatGPT,
            notificationPID: userNotificationCenter,
            helperPID: menuBarHelper,
            selfPID: selfApp,
        ]

        var coldResolver = FocusTargetResolver(selfPID: selfPID)
        let coldResolution = coldResolver.resolve(
            currentFrontmost: userNotificationCenter,
            excludedBundleIDs: [],
            observedWindows: observedWindows,
            fallbackAppProvider: { appsByPID[$0] }
        )
        XCTAssertEqual(coldResolution, .active(chatGPT))
        XCTAssertEqual(coldResolver.lastExternalFrontmostApp, chatGPT)

        let helperNoLayer0Resolution = coldResolver.resolve(
            currentFrontmost: menuBarHelper,
            excludedBundleIDs: [],
            observedWindows: observedWindows,
            fallbackAppProvider: { appsByPID[$0] }
        )
        XCTAssertEqual(helperNoLayer0Resolution, .active(chatGPT))
        XCTAssertEqual(coldResolver.lastExternalFrontmostApp, chatGPT)

        var selfColdResolver = FocusTargetResolver(selfPID: selfPID)
        let selfColdResolution = selfColdResolver.resolve(
            currentFrontmost: selfApp,
            excludedBundleIDs: [],
            observedWindows: observedWindows,
            fallbackAppProvider: { appsByPID[$0] }
        )
        XCTAssertEqual(selfColdResolution, .active(chatGPT))
    }

    func testLaunchOptionsFocusDiagnosticOverridesAndClamping() {
        let parsed = LaunchOptions.parse(
            arguments: [
                "DimWallpaper",
                "--defaults-suite", "audit.focus.suite",
                "--focus-enabled", "true",
                "--focus-intensity", "0.95",
                "--dim-menubar=true",
                "--dim-dock", "false",
                "--focus-scope", "frontWindow",
            ],
            environment: [:]
        )
        XCTAssertTrue(parsed.hasFocusOverrides)
        XCTAssertEqual(parsed.focusEnabledOverride, true)
        XCTAssertEqual(parsed.focusIntensityOverride ?? 0, FocusBounds.maximumIntensity, accuracy: 0.0001)
        XCTAssertEqual(parsed.dimMenuBarOverride, true)
        XCTAssertEqual(parsed.dimDockOverride, false)
        XCTAssertEqual(parsed.focusScopeOverride, .frontWindow)

        let overridden = parsed.applyingOverrides(to: DimmingSnapshot())
        XCTAssertTrue(overridden.focusEnabled)
        XCTAssertEqual(overridden.focusIntensity, FocusBounds.maximumIntensity, accuracy: 0.0001)
        XCTAssertTrue(overridden.dimMenuBar)
        XCTAssertFalse(overridden.dimDock)
        XCTAssertEqual(overridden.focusScope, .frontWindow)
    }

    func testDualHotKeysFocusPreferencesRoundTripAndLegacyBackwardCompatibility() throws {
        defaults.set(true, forKey: PreferenceKey.enabled)
        defaults.set(0.55, forKey: PreferenceKey.intensity)
        defaults.set(false, forKey: PreferenceKey.darkOnly)
        defaults.set(DimmingTint.warmNight.rawValue, forKey: PreferenceKey.tint)
        defaults.set(Int(2), forKey: PreferenceKey.hotKeyKeyCode)
        defaults.set(Int(HotKeyBinding.optionMask | HotKeyBinding.commandMask), forKey: PreferenceKey.hotKeyModifiers)

        let store = PreferencesStore(userDefaults: defaults, suiteName: suiteName)
        let migrated = store.load()
        XCTAssertTrue(migrated.enabled)
        XCTAssertEqual(migrated.intensity, 0.55, accuracy: 0.0001)
        XCTAssertFalse(migrated.darkOnly)
        XCTAssertEqual(migrated.tint, .warmNight)
        XCTAssertEqual(migrated.hotKeyBinding.displayLabel, "⌥⌘D")
        XCTAssertFalse(migrated.focusEnabled)
        XCTAssertEqual(migrated.focusIntensity, FocusBounds.defaultIntensity, accuracy: 0.0001)
        XCTAssertEqual(migrated.focusTint, .followWallpaper)
        XCTAssertEqual(migrated.focusScope, .frontApplication)
        XCTAssertFalse(migrated.dimMenuBar)
        XCTAssertFalse(migrated.dimDock)
        XCTAssertEqual(migrated.focusMultiDisplayPolicy, .dimInactiveScreens)
        XCTAssertEqual(migrated.focusTransitionSpeed, .gentle)
        XCTAssertTrue(migrated.focusExcludedBundleIDs.isEmpty)
        XCTAssertTrue(migrated.focusHotKeyEnabled)
        XCTAssertEqual(migrated.focusHotKeyBinding, .defaultFocusToggle)

        let legacyJSON = """
        {
          "enabled": true,
          "intensity": 0.45,
          "darkOnly": true,
          "tint": "coolSlate",
          "excludedDisplayIDs": [3],
          "hotKeyEnabled": true,
          "hotKeyBinding": { "keyCode": 2, "modifiers": 2304 }
        }
        """
        let decodedLegacy = try JSONDecoder().decode(DimmingSnapshot.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decodedLegacy.tint, .coolSlate)
        XCTAssertEqual(decodedLegacy.excludedDisplayIDs, [3])
        XCTAssertEqual(decodedLegacy.hotKeyBinding.displayLabel, "⌥⌘D")
        XCTAssertFalse(decodedLegacy.focusEnabled)
        XCTAssertEqual(decodedLegacy.focusIntensity, FocusBounds.defaultIntensity, accuracy: 0.0001)
        XCTAssertEqual(decodedLegacy.focusHotKeyBinding, .defaultFocusToggle)

        let fullV2 = DimmingSnapshot(
            enabled: true,
            intensity: 0.35,
            darkOnly: true,
            tint: .coolSlate,
            excludedDisplayIDs: [2],
            hotKeyEnabled: true,
            hotKeyBinding: .defaultToggle,
            focusEnabled: true,
            focusIntensity: 0.70,
            focusTint: .warmNight,
            focusScope: .frontWindow,
            dimMenuBar: true,
            dimDock: true,
            focusMultiDisplayPolicy: .activeScreenOnly,
            focusTransitionSpeed: .snappy,
            focusExcludedBundleIDs: ["  com.apple.finder  ", "", "com.apple.Preview"],
            focusHotKeyEnabled: false,
            focusHotKeyBinding: HotKeyBinding(keyCode: 5, modifiers: HotKeyBinding.controlMask | HotKeyBinding.commandMask)
        )
        store.save(fullV2)
        let reloadedV2 = store.load()
        XCTAssertTrue(reloadedV2.focusEnabled)
        XCTAssertEqual(reloadedV2.focusIntensity, 0.70, accuracy: 0.0001)
        XCTAssertEqual(reloadedV2.focusTint, .warmNight)
        XCTAssertEqual(reloadedV2.focusScope, .frontWindow)
        XCTAssertTrue(reloadedV2.dimMenuBar)
        XCTAssertTrue(reloadedV2.dimDock)
        XCTAssertEqual(reloadedV2.focusMultiDisplayPolicy, .activeScreenOnly)
        XCTAssertEqual(reloadedV2.focusTransitionSpeed, .snappy)
        XCTAssertEqual(reloadedV2.focusExcludedBundleIDs, ["com.apple.finder", "com.apple.Preview"])
        XCTAssertFalse(reloadedV2.focusHotKeyEnabled)
        XCTAssertEqual(reloadedV2.focusHotKeyBinding.displayLabel, "⌃⌘G")

        defaults.set(9.9, forKey: PreferenceKey.focusIntensity)
        defaults.set("invalid-scope", forKey: PreferenceKey.focusScope)
        defaults.set("invalid-tint", forKey: PreferenceKey.focusTint)
        defaults.set(0, forKey: PreferenceKey.focusHotKeyModifiers)
        let sanitizedV2 = store.load()
        XCTAssertEqual(sanitizedV2.focusIntensity, FocusBounds.maximumIntensity, accuracy: 0.0001)
        XCTAssertEqual(sanitizedV2.focusScope, .frontApplication)
        XCTAssertEqual(sanitizedV2.focusTint, .followWallpaper)
        XCTAssertEqual(sanitizedV2.focusHotKeyBinding, .defaultFocusToggle)

        var engine = DimmingEngineState(snapshot: reloadedV2, isDarkAppearance: true, displays: [])
        XCTAssertEqual(engine.statusSymbolName, "moon.stars.fill")
        XCTAssertEqual(engine.statusBadgeTitle, "双重沉浸")
        XCTAssertTrue(engine.statusSummary.contains("双重沉浸"))
        XCTAssertEqual(engine.resolvedFocusTint, .warmNight)
        engine.setFocusTint(.followWallpaper)
        XCTAssertEqual(engine.resolvedFocusTint, .coolSlate)
        engine.setEnabled(false)
        XCTAssertEqual(engine.statusSymbolName, "viewfinder")
        XCTAssertTrue(engine.statusBadgeTitle.contains("专注中"))
        XCTAssertTrue(engine.statusSummary.contains("含栏"))

        let report = DiagnosticReport(
            version: "1.1.0",
            suiteName: suiteName,
            snapshot: reloadedV2,
            displays: [],
            loginItemStatus: 1
        )
        XCTAssertTrue(report.legacyLine().contains("focusEnabled=true focusIntensity=0.7 focusScope=frontWindow dimMenuBar=true dimDock=true focusHotKeyEnabled=false"))
        let decodedReport = try JSONDecoder().decode(DiagnosticReport.self, from: Data(try report.jsonString().utf8))
        XCTAssertEqual(decodedReport, report)
    }

    private func assertPartitionDisjoint(
        _ rects: [CGRect],
        expectedTotalArea: CGFloat,
        inside bounds: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var totalArea: CGFloat = 0
        for index in rects.indices {
            let rect = rects[index]
            XCTAssertTrue(bounds.contains(rect), "Rect \(rect) escapes screen bounds \(bounds)", file: file, line: line)
            totalArea += rect.width * rect.height
            for otherIndex in (index + 1)..<rects.count {
                let overlap = rect.intersection(rects[otherIndex])
                let overlapArea = (overlap.isNull || overlap.isEmpty) ? 0 : overlap.width * overlap.height
                XCTAssertEqual(overlapArea, 0, accuracy: 0.01, "Rects overlap: \(rect) vs \(rects[otherIndex])", file: file, line: line)
            }
        }
        XCTAssertEqual(totalArea, expectedTotalArea, accuracy: 1.0, file: file, line: line)
    }
}
