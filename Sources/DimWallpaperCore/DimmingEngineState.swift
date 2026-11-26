import Foundation

public struct DimmingEngineState: Equatable, Sendable {
    public var snapshot: DimmingSnapshot
    public var isDarkAppearance: Bool
    public var displays: [DisplayDescriptor]

    public init(
        snapshot: DimmingSnapshot = DimmingSnapshot(),
        isDarkAppearance: Bool = true,
        displays: [DisplayDescriptor] = []
    ) {
        self.snapshot = snapshot
        self.isDarkAppearance = isDarkAppearance
        self.displays = displays
    }

    public var intensityPercent: Int {
        DimmingBounds.percentage(for: snapshot.intensity)
    }

    public var activePreset: DimmingPreset? {
        DimmingPreset.matching(intensity: snapshot.intensity)
    }

    public var focusIntensityPercent: Int {
        FocusBounds.percentage(for: snapshot.focusIntensity)
    }

    public var activeFocusPreset: FocusPreset? {
        FocusPreset.matching(intensity: snapshot.focusIntensity)
    }

    public var resolvedFocusTint: DimmingTint {
        snapshot.focusTint.resolvedTint(wallpaperTint: snapshot.tint)
    }

    public var isFocusGloballyActive: Bool {
        snapshot.focusEnabled && snapshot.focusIntensity > FocusBounds.visibilityEpsilon
    }

    public var effectiveFocusPreviewAlpha: Double {
        isFocusGloballyActive ? FocusBounds.clampedIntensity(snapshot.focusIntensity) : 0
    }

    public var focusSystemBarPreset: FocusSystemBarPreset? {
        FocusSystemBarPreset.matching(dimMenuBar: snapshot.dimMenuBar, dimDock: snapshot.dimDock)
    }

    public func isAppExcludedFromFocus(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return snapshot.focusExcludedBundleIDs.contains(bundleID)
    }

    public var isGloballyActive: Bool {
        snapshot.enabled
            && snapshot.intensity > DimmingBounds.visibilityEpsilon
            && (isDarkAppearance || !snapshot.darkOnly)
    }

    public var activeDisplayCount: Int {
        guard isGloballyActive else { return 0 }
        return displays.filter { !snapshot.excludedDisplayIDs.contains($0.id) }.count
    }

    public var isDimmingAnyDisplay: Bool {
        guard isGloballyActive else { return false }
        if displays.isEmpty { return true }
        return activeDisplayCount > 0
    }

    public var effectivePreviewAlpha: Double {
        isDimmingAnyDisplay ? DimmingBounds.clampedIntensity(snapshot.intensity) : 0
    }

    public var statusSymbolName: String {
        if isDimmingAnyDisplay && isFocusGloballyActive {
            return "moon.stars.fill"
        }
        if isFocusGloballyActive {
            return "viewfinder"
        }
        if !snapshot.enabled {
            return "circle.slash"
        }
        if isDimmingAnyDisplay {
            return "moon.fill"
        }
        return "sun.max"
    }

    public var statusBadgeTitle: String {
        if isDimmingAnyDisplay && isFocusGloballyActive {
            return "双重沉浸"
        }
        if isFocusGloballyActive {
            return "专注中 · \(focusIntensityPercent)%"
        }
        if !snapshot.enabled {
            return "已暂停"
        }
        if !isGloballyActive {
            return "浅色待命"
        }
        if !displays.isEmpty && activeDisplayCount == 0 {
            return "全部豁免"
        }
        return "压暗中 · \(intensityPercent)%"
    }

    public var statusSummary: String {
        if isDimmingAnyDisplay && isFocusGloballyActive {
            return "双重沉浸 · 壁纸 \(intensityPercent)% / 专注 \(focusIntensityPercent)%"
        }
        if isFocusGloballyActive {
            let barLabel = (snapshot.dimMenuBar && snapshot.dimDock)
                ? "含栏"
                : ((snapshot.dimMenuBar || snapshot.dimDock) ? "部分栏" : "留栏")
            return "专注遮罩 · \(focusIntensityPercent)%（\(snapshot.focusScope.shortTitle) · \(barLabel)）"
        }
        let appearanceLabel = isDarkAppearance ? "深色" : "浅色"
        if !snapshot.enabled {
            return "已暂停 · 壁纸原色"
        }
        if !isGloballyActive {
            return "\(appearanceLabel)模式 · 保持原色"
        }
        if !displays.isEmpty && activeDisplayCount == 0 {
            return "\(appearanceLabel)模式 · 全部屏幕已豁免"
        }
        if displays.count > 1 && activeDisplayCount < displays.count {
            return "\(appearanceLabel)模式 · \(activeDisplayCount)/\(displays.count) 屏已调暗 \(intensityPercent)%"
        }
        return "\(appearanceLabel)模式 · 壁纸已调暗 \(intensityPercent)%"
    }

    public func isDisplayExcluded(_ displayID: UInt32) -> Bool {
        snapshot.excludedDisplayIDs.contains(displayID)
    }

    public func decision(for displayID: UInt32) -> DisplayOverlayDecision {
        let excluded = snapshot.excludedDisplayIDs.contains(displayID)
        let targetAlpha = (isGloballyActive && !excluded)
            ? DimmingBounds.clampedIntensity(snapshot.intensity)
            : 0
        return DisplayOverlayDecision(
            displayID: displayID,
            isExcluded: excluded,
            targetAlpha: targetAlpha
        )
    }

    public func overlayDecisions() -> [DisplayOverlayDecision] {
        displays.map { decision(for: $0.id) }
    }

    public func staleDisplayIDs(existingWindowIDs: Set<UInt32>) -> [UInt32] {
        let onlineIDs = Set(displays.map(\.id))
        return existingWindowIDs.subtracting(onlineIDs).sorted()
    }

    public mutating func setEnabled(_ value: Bool) {
        snapshot.enabled = value
    }

    public mutating func toggleEnabled() {
        snapshot.enabled.toggle()
    }

    public mutating func setIntensity(_ value: Double) {
        snapshot.intensity = DimmingBounds.clampedIntensity(value)
    }

    public mutating func applyPreset(_ preset: DimmingPreset) {
        snapshot.intensity = preset.intensity
    }

    public mutating func setDarkOnly(_ value: Bool) {
        snapshot.darkOnly = value
    }

    public mutating func setTint(_ value: DimmingTint) {
        snapshot.tint = value
    }

    public mutating func setDisplayExcluded(_ displayID: UInt32, excluded: Bool) {
        if excluded {
            snapshot.excludedDisplayIDs.insert(displayID)
        } else {
            snapshot.excludedDisplayIDs.remove(displayID)
        }
    }

    public mutating func setHotKeyEnabled(_ value: Bool) {
        snapshot.hotKeyEnabled = value
    }

    public mutating func setFocusEnabled(_ value: Bool) {
        snapshot.focusEnabled = value
    }

    public mutating func toggleFocusEnabled() {
        snapshot.focusEnabled.toggle()
    }

    public mutating func setFocusIntensity(_ value: Double) {
        snapshot.focusIntensity = FocusBounds.clampedIntensity(value)
    }

    public mutating func applyFocusPreset(_ preset: FocusPreset) {
        snapshot.focusEnabled = true
        snapshot.focusIntensity = FocusBounds.clampedIntensity(preset.intensity)
    }

    public mutating func setFocusTint(_ value: FocusTintOption) {
        snapshot.focusTint = value
    }

    public mutating func setFocusScope(_ value: FocusScope) {
        snapshot.focusScope = value
    }

    public mutating func setDimMenuBar(_ value: Bool) {
        snapshot.dimMenuBar = value
    }

    public mutating func setDimDock(_ value: Bool) {
        snapshot.dimDock = value
    }

    public mutating func applyFocusSystemBarPreset(_ preset: FocusSystemBarPreset) {
        switch preset {
        case .keepSystemBars:
            snapshot.dimMenuBar = false
            snapshot.dimDock = false
        case .dimAll:
            snapshot.dimMenuBar = true
            snapshot.dimDock = true
        }
    }

    public mutating func setFocusMultiDisplayPolicy(_ value: FocusMultiDisplayPolicy) {
        snapshot.focusMultiDisplayPolicy = value
    }

    public mutating func setPauseFocusOnFullscreen(_ value: Bool) {
        snapshot.pauseFocusOnFullscreen = value
    }

    public mutating func setFocusEdgeFeather(_ value: FocusEdgeFeather) {
        snapshot.focusEdgeFeather = value
    }

    public mutating func setFocusTransitionSpeed(_ value: FocusTransitionSpeed) {
        snapshot.focusTransitionSpeed = value
    }

    public mutating func setFocusExcludedApp(_ bundleID: String, excluded: Bool) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if excluded {
            snapshot.focusExcludedBundleIDs.insert(trimmed)
        } else {
            snapshot.focusExcludedBundleIDs.remove(trimmed)
        }
    }

    public mutating func setFocusHotKeyEnabled(_ value: Bool) {
        snapshot.focusHotKeyEnabled = value
    }

    public mutating func updateDisplays(_ nextDisplays: [DisplayDescriptor]) {
        displays = nextDisplays
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public let version: String
    public let suiteName: String?
    public let enabled: Bool
    public let intensity: Double
    public let intensityPercent: Int
    public let darkOnly: Bool
    public let tint: String
    public let hotKeyEnabled: Bool
    public let hotKey: String
    public let excludedDisplayIDs: [UInt32]
    public let focusEnabled: Bool
    public let focusIntensity: Double
    public let focusIntensityPercent: Int
    public let focusTint: String
    public let focusScope: String
    public let dimMenuBar: Bool
    public let dimDock: Bool
    public let focusMultiDisplayPolicy: String
    public let pauseFocusOnFullscreen: Bool
    public let focusEdgeFeather: String
    public let focusTransitionSpeed: String
    public let focusExcludedBundleIDs: [String]
    public let focusHotKeyEnabled: Bool
    public let focusHotKey: String
    public let displays: [DisplayDescriptor]
    public let loginItemStatus: Int

    public init(
        version: String,
        suiteName: String?,
        snapshot: DimmingSnapshot,
        displays: [DisplayDescriptor],
        loginItemStatus: Int
    ) {
        self.version = version
        self.suiteName = suiteName
        self.enabled = snapshot.enabled
        self.intensity = DimmingBounds.clampedIntensity(snapshot.intensity)
        self.intensityPercent = DimmingBounds.percentage(for: snapshot.intensity)
        self.darkOnly = snapshot.darkOnly
        self.tint = snapshot.tint.rawValue
        self.hotKeyEnabled = snapshot.hotKeyEnabled
        self.hotKey = snapshot.hotKeyBinding.displayLabel
        self.excludedDisplayIDs = snapshot.excludedDisplayIDs.sorted()
        self.focusEnabled = snapshot.focusEnabled
        self.focusIntensity = FocusBounds.clampedIntensity(snapshot.focusIntensity)
        self.focusIntensityPercent = FocusBounds.percentage(for: snapshot.focusIntensity)
        self.focusTint = snapshot.focusTint.rawValue
        self.focusScope = snapshot.focusScope.rawValue
        self.dimMenuBar = snapshot.dimMenuBar
        self.dimDock = snapshot.dimDock
        self.focusMultiDisplayPolicy = snapshot.focusMultiDisplayPolicy.rawValue
        self.pauseFocusOnFullscreen = snapshot.pauseFocusOnFullscreen
        self.focusEdgeFeather = snapshot.focusEdgeFeather.rawValue
        self.focusTransitionSpeed = snapshot.focusTransitionSpeed.rawValue
        self.focusExcludedBundleIDs = snapshot.focusExcludedBundleIDs.sorted()
        self.focusHotKeyEnabled = snapshot.focusHotKeyEnabled
        self.focusHotKey = snapshot.focusHotKeyBinding.displayLabel
        self.displays = displays
        self.loginItemStatus = loginItemStatus
    }

    public func legacyLine() -> String {
        "enabled=\(enabled) intensity=\(intensity) darkOnly=\(darkOnly) tint=\(tint) hotKeyEnabled=\(hotKeyEnabled) focusEnabled=\(focusEnabled) focusIntensity=\(focusIntensity) focusScope=\(focusScope) dimMenuBar=\(dimMenuBar) dimDock=\(dimDock) focusHotKeyEnabled=\(focusHotKeyEnabled) displays=\(displays.count) loginItemStatus=\(loginItemStatus) focusMultiDisplayPolicy=\(focusMultiDisplayPolicy) pauseFocusOnFullscreen=\(pauseFocusOnFullscreen) focusEdgeFeather=\(focusEdgeFeather) focusTransitionSpeed=\(focusTransitionSpeed)"
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
