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
        if !snapshot.enabled {
            return "circle.slash"
        }
        if isDimmingAnyDisplay {
            return "moon.fill"
        }
        return "sun.max"
    }

    public var statusBadgeTitle: String {
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
        self.displays = displays
        self.loginItemStatus = loginItemStatus
    }

    public func legacyLine() -> String {
        "enabled=\(enabled) intensity=\(intensity) darkOnly=\(darkOnly) tint=\(tint) hotKeyEnabled=\(hotKeyEnabled) displays=\(displays.count) loginItemStatus=\(loginItemStatus)"
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
