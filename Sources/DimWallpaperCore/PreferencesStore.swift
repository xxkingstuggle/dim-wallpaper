import Foundation

public enum PreferenceKey {
    public static let enabled = "enabled"
    public static let intensity = "intensity"
    public static let darkOnly = "darkOnly"
    public static let didSetupLoginItem = "didSetupLoginItem"
    public static let tint = "tint"
    public static let excludedDisplayIDs = "excludedDisplayIDs"
    public static let hotKeyEnabled = "hotKeyEnabled"
    public static let hotKeyKeyCode = "hotKeyKeyCode"
    public static let hotKeyModifiers = "hotKeyModifiers"
}

public struct DimmingSnapshot: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var intensity: Double
    public var darkOnly: Bool
    public var tint: DimmingTint
    public var excludedDisplayIDs: Set<UInt32>
    public var hotKeyEnabled: Bool
    public var hotKeyBinding: HotKeyBinding

    public init(
        enabled: Bool = true,
        intensity: Double = DimmingBounds.defaultIntensity,
        darkOnly: Bool = true,
        tint: DimmingTint = .neutral,
        excludedDisplayIDs: Set<UInt32> = [],
        hotKeyEnabled: Bool = true,
        hotKeyBinding: HotKeyBinding = .defaultToggle
    ) {
        self.enabled = enabled
        self.intensity = DimmingBounds.clampedIntensity(intensity)
        self.darkOnly = darkOnly
        self.tint = tint
        self.excludedDisplayIDs = excludedDisplayIDs
        self.hotKeyEnabled = hotKeyEnabled
        self.hotKeyBinding = hotKeyBinding.isValid ? hotKeyBinding : .defaultToggle
    }
}

public final class PreferencesStore {
    public let suiteName: String?
    private let defaults: UserDefaults

    public init(suiteName: String? = nil) {
        let trimmed = suiteName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty, let suiteDefaults = UserDefaults(suiteName: trimmed) {
            self.suiteName = trimmed
            self.defaults = suiteDefaults
        } else {
            self.suiteName = nil
            self.defaults = .standard
        }
        registerDefaults()
    }

    public init(userDefaults: UserDefaults, suiteName: String? = nil) {
        self.suiteName = suiteName
        self.defaults = userDefaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            PreferenceKey.enabled: true,
            PreferenceKey.intensity: DimmingBounds.defaultIntensity,
            PreferenceKey.darkOnly: true,
            PreferenceKey.tint: DimmingTint.neutral.rawValue,
            PreferenceKey.excludedDisplayIDs: [Int](),
            PreferenceKey.hotKeyEnabled: true,
            PreferenceKey.hotKeyKeyCode: Int(HotKeyBinding.defaultToggle.keyCode),
            PreferenceKey.hotKeyModifiers: Int(HotKeyBinding.defaultToggle.modifiers),
        ])
    }

    public func load() -> DimmingSnapshot {
        let enabled = defaults.bool(forKey: PreferenceKey.enabled)
        let rawIntensity = defaults.double(forKey: PreferenceKey.intensity)
        let darkOnly = defaults.bool(forKey: PreferenceKey.darkOnly)
        let rawTint = defaults.string(forKey: PreferenceKey.tint) ?? DimmingTint.neutral.rawValue
        let tint = DimmingTint(rawValue: rawTint) ?? .neutral

        let rawExcluded = defaults.array(forKey: PreferenceKey.excludedDisplayIDs) ?? []
        var excludedIDs = Set<UInt32>()
        for entry in rawExcluded {
            if let number = entry as? NSNumber {
                let intValue = number.int64Value
                if intValue >= 0, intValue <= Int64(UInt32.max) {
                    excludedIDs.insert(UInt32(intValue))
                }
            }
        }

        let hotKeyEnabled = defaults.bool(forKey: PreferenceKey.hotKeyEnabled)
        let keyCode = defaults.integer(forKey: PreferenceKey.hotKeyKeyCode)
        let modifiers = defaults.integer(forKey: PreferenceKey.hotKeyModifiers)
        let candidateBinding: HotKeyBinding
        if keyCode >= 0, keyCode <= Int(UInt32.max), modifiers >= 0, modifiers <= Int(UInt32.max) {
            candidateBinding = HotKeyBinding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        } else {
            candidateBinding = .defaultToggle
        }

        return DimmingSnapshot(
            enabled: enabled,
            intensity: DimmingBounds.clampedIntensity(rawIntensity),
            darkOnly: darkOnly,
            tint: tint,
            excludedDisplayIDs: excludedIDs,
            hotKeyEnabled: hotKeyEnabled,
            hotKeyBinding: candidateBinding.isValid ? candidateBinding : .defaultToggle
        )
    }

    public func save(_ snapshot: DimmingSnapshot) {
        let clampedIntensity = DimmingBounds.clampedIntensity(snapshot.intensity)
        let validBinding = snapshot.hotKeyBinding.isValid ? snapshot.hotKeyBinding : .defaultToggle
        defaults.set(snapshot.enabled, forKey: PreferenceKey.enabled)
        defaults.set(clampedIntensity, forKey: PreferenceKey.intensity)
        defaults.set(snapshot.darkOnly, forKey: PreferenceKey.darkOnly)
        defaults.set(snapshot.tint.rawValue, forKey: PreferenceKey.tint)
        defaults.set(snapshot.excludedDisplayIDs.sorted().map { NSNumber(value: $0) }, forKey: PreferenceKey.excludedDisplayIDs)
        defaults.set(snapshot.hotKeyEnabled, forKey: PreferenceKey.hotKeyEnabled)
        defaults.set(Int(validBinding.keyCode), forKey: PreferenceKey.hotKeyKeyCode)
        defaults.set(Int(validBinding.modifiers), forKey: PreferenceKey.hotKeyModifiers)
    }

    public var didSetupLoginItem: Bool {
        get { defaults.bool(forKey: PreferenceKey.didSetupLoginItem) }
        set { defaults.set(newValue, forKey: PreferenceKey.didSetupLoginItem) }
    }
}
