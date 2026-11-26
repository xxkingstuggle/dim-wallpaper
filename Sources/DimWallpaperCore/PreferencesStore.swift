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
    public static let focusEnabled = "focusEnabled"
    public static let focusIntensity = "focusIntensity"
    public static let focusTint = "focusTint"
    public static let focusScope = "focusScope"
    public static let focusDimMenuBar = "focusDimMenuBar"
    public static let focusDimDock = "focusDimDock"
    public static let focusMultiDisplayPolicy = "focusMultiDisplayPolicy"
    public static let focusPauseOnFullscreen = "focusPauseOnFullscreen"
    public static let focusTransitionSpeed = "focusTransitionSpeed"
    public static let focusTransitionStyle = "focusTransitionStyle"
    public static let focusTransitionDuration = "focusTransitionDuration"
    public static let focusExcludedBundleIDs = "focusExcludedBundleIDs"
    public static let focusHotKeyEnabled = "focusHotKeyEnabled"
    public static let focusHotKeyKeyCode = "focusHotKeyKeyCode"
    public static let focusHotKeyModifiers = "focusHotKeyModifiers"
}

public struct DimmingSnapshot: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var intensity: Double
    public var darkOnly: Bool
    public var tint: DimmingTint
    public var excludedDisplayIDs: Set<UInt32>
    public var hotKeyEnabled: Bool
    public var hotKeyBinding: HotKeyBinding
    public var focusEnabled: Bool
    public var focusIntensity: Double
    public var focusTint: FocusTintOption
    public var focusScope: FocusScope
    public var dimMenuBar: Bool
    public var dimDock: Bool
    public var focusMultiDisplayPolicy: FocusMultiDisplayPolicy
    public var pauseFocusOnFullscreen: Bool
    public var focusTransitionSpeed: FocusTransitionSpeed
    public var focusTransitionStyle: FocusTransitionStyle
    public var focusTransitionDuration: Double
    public var focusExcludedBundleIDs: Set<String>
    public var focusHotKeyEnabled: Bool
    public var focusHotKeyBinding: HotKeyBinding

    public init(
        enabled: Bool = true,
        intensity: Double = DimmingBounds.defaultIntensity,
        darkOnly: Bool = true,
        tint: DimmingTint = .neutral,
        excludedDisplayIDs: Set<UInt32> = [],
        hotKeyEnabled: Bool = true,
        hotKeyBinding: HotKeyBinding = .defaultToggle,
        focusEnabled: Bool = false,
        focusIntensity: Double = FocusBounds.defaultIntensity,
        focusTint: FocusTintOption = .followWallpaper,
        focusScope: FocusScope = .frontApplication,
        dimMenuBar: Bool = false,
        dimDock: Bool = false,
        focusMultiDisplayPolicy: FocusMultiDisplayPolicy = .perDisplayFront,
        pauseFocusOnFullscreen: Bool = true,
        focusTransitionSpeed: FocusTransitionSpeed = .softBreath,
        focusTransitionStyle: FocusTransitionStyle = .fluidEase,
        focusTransitionDuration: Double = FocusBounds.defaultTransitionDuration,
        focusExcludedBundleIDs: Set<String> = [],
        focusHotKeyEnabled: Bool = true,
        focusHotKeyBinding: HotKeyBinding = .defaultFocusToggle
    ) {
        self.enabled = enabled
        self.intensity = DimmingBounds.clampedIntensity(intensity)
        self.darkOnly = darkOnly
        self.tint = tint
        self.excludedDisplayIDs = excludedDisplayIDs
        self.hotKeyEnabled = hotKeyEnabled
        self.hotKeyBinding = hotKeyBinding.isValid ? hotKeyBinding : .defaultToggle
        self.focusEnabled = focusEnabled
        self.focusIntensity = FocusBounds.clampedIntensity(focusIntensity)
        self.focusTint = focusTint
        self.focusScope = focusScope
        self.dimMenuBar = dimMenuBar
        self.dimDock = dimDock
        self.focusMultiDisplayPolicy = focusMultiDisplayPolicy
        self.pauseFocusOnFullscreen = pauseFocusOnFullscreen
        self.focusTransitionSpeed = focusTransitionSpeed
        self.focusTransitionStyle = focusTransitionStyle
        self.focusTransitionDuration = FocusBounds.clampedTransitionDuration(focusTransitionDuration)
        self.focusExcludedBundleIDs = focusExcludedBundleIDs
        self.focusHotKeyEnabled = focusHotKeyEnabled
        self.focusHotKeyBinding = focusHotKeyBinding.isValid ? focusHotKeyBinding : .defaultFocusToggle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let decodedIntensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? DimmingBounds.defaultIntensity
        let decodedDarkOnly = try container.decodeIfPresent(Bool.self, forKey: .darkOnly) ?? true
        let decodedTint = try container.decodeIfPresent(DimmingTint.self, forKey: .tint) ?? .neutral
        let decodedExcludedDisplays = try container.decodeIfPresent(Set<UInt32>.self, forKey: .excludedDisplayIDs) ?? []
        let decodedHotKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotKeyEnabled) ?? true
        let decodedHotKeyBinding = try container.decodeIfPresent(HotKeyBinding.self, forKey: .hotKeyBinding) ?? .defaultToggle
        let decodedFocusEnabled = try container.decodeIfPresent(Bool.self, forKey: .focusEnabled) ?? false
        let decodedFocusIntensity = try container.decodeIfPresent(Double.self, forKey: .focusIntensity) ?? FocusBounds.defaultIntensity
        let decodedFocusTint = try container.decodeIfPresent(FocusTintOption.self, forKey: .focusTint) ?? .followWallpaper
        let decodedFocusScope = try container.decodeIfPresent(FocusScope.self, forKey: .focusScope) ?? .frontApplication
        let decodedDimMenuBar = try container.decodeIfPresent(Bool.self, forKey: .dimMenuBar) ?? false
        let decodedDimDock = try container.decodeIfPresent(Bool.self, forKey: .dimDock) ?? false
        let decodedPolicy = try container.decodeIfPresent(FocusMultiDisplayPolicy.self, forKey: .focusMultiDisplayPolicy) ?? .perDisplayFront
        let decodedPauseOnFullscreen = try container.decodeIfPresent(Bool.self, forKey: .pauseFocusOnFullscreen) ?? true
        let decodedSpeed = try container.decodeIfPresent(FocusTransitionSpeed.self, forKey: .focusTransitionSpeed) ?? .softBreath
        let decodedTransitionStyle = try container.decodeIfPresent(FocusTransitionStyle.self, forKey: .focusTransitionStyle)
            ?? FocusTransitionStyle.migratedStyle(fromLegacySpeed: decodedSpeed)
        let decodedTransitionDuration = try container.decodeIfPresent(Double.self, forKey: .focusTransitionDuration)
            ?? FocusTransitionStyle.migratedDuration(fromLegacySpeed: decodedSpeed)
        let decodedExcludedApps = try container.decodeIfPresent(Set<String>.self, forKey: .focusExcludedBundleIDs) ?? []
        let decodedFocusHotKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .focusHotKeyEnabled) ?? true
        let decodedFocusHotKeyBinding = try container.decodeIfPresent(HotKeyBinding.self, forKey: .focusHotKeyBinding) ?? .defaultFocusToggle

        self.init(
            enabled: decodedEnabled,
            intensity: decodedIntensity,
            darkOnly: decodedDarkOnly,
            tint: decodedTint,
            excludedDisplayIDs: decodedExcludedDisplays,
            hotKeyEnabled: decodedHotKeyEnabled,
            hotKeyBinding: decodedHotKeyBinding,
            focusEnabled: decodedFocusEnabled,
            focusIntensity: decodedFocusIntensity,
            focusTint: decodedFocusTint,
            focusScope: decodedFocusScope,
            dimMenuBar: decodedDimMenuBar,
            dimDock: decodedDimDock,
            focusMultiDisplayPolicy: decodedPolicy,
            pauseFocusOnFullscreen: decodedPauseOnFullscreen,
            focusTransitionSpeed: decodedSpeed,
            focusTransitionStyle: decodedTransitionStyle,
            focusTransitionDuration: decodedTransitionDuration,
            focusExcludedBundleIDs: decodedExcludedApps,
            focusHotKeyEnabled: decodedFocusHotKeyEnabled,
            focusHotKeyBinding: decodedFocusHotKeyBinding
        )
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
            PreferenceKey.focusEnabled: false,
            PreferenceKey.focusIntensity: FocusBounds.defaultIntensity,
            PreferenceKey.focusTint: FocusTintOption.followWallpaper.rawValue,
            PreferenceKey.focusScope: FocusScope.frontApplication.rawValue,
            PreferenceKey.focusDimMenuBar: false,
            PreferenceKey.focusDimDock: false,
            PreferenceKey.focusMultiDisplayPolicy: FocusMultiDisplayPolicy.perDisplayFront.rawValue,
            PreferenceKey.focusPauseOnFullscreen: true,
            PreferenceKey.focusTransitionSpeed: FocusTransitionSpeed.softBreath.rawValue,
            PreferenceKey.focusExcludedBundleIDs: [String](),
            PreferenceKey.focusHotKeyEnabled: true,
            PreferenceKey.focusHotKeyKeyCode: Int(HotKeyBinding.defaultFocusToggle.keyCode),
            PreferenceKey.focusHotKeyModifiers: Int(HotKeyBinding.defaultFocusToggle.modifiers),
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
        let candidateBinding = loadHotKeyBinding(
            keyCodeKey: PreferenceKey.hotKeyKeyCode,
            modifiersKey: PreferenceKey.hotKeyModifiers,
            fallback: .defaultToggle
        )

        let focusEnabled = defaults.bool(forKey: PreferenceKey.focusEnabled)
        let rawFocusIntensity = defaults.double(forKey: PreferenceKey.focusIntensity)
        let rawFocusTint = defaults.string(forKey: PreferenceKey.focusTint) ?? FocusTintOption.followWallpaper.rawValue
        let focusTint = FocusTintOption(rawValue: rawFocusTint) ?? .followWallpaper
        let rawFocusScope = defaults.string(forKey: PreferenceKey.focusScope) ?? FocusScope.frontApplication.rawValue
        let focusScope = FocusScope(rawValue: rawFocusScope) ?? .frontApplication
        let dimMenuBar = defaults.bool(forKey: PreferenceKey.focusDimMenuBar)
        let dimDock = defaults.bool(forKey: PreferenceKey.focusDimDock)
        let rawPolicy = defaults.string(forKey: PreferenceKey.focusMultiDisplayPolicy)
        let focusMultiDisplayPolicy = FocusMultiDisplayPolicy.fromStoredValue(rawPolicy)
        if rawPolicy == "dimInactiveScreens" {
            defaults.set(focusMultiDisplayPolicy.rawValue, forKey: PreferenceKey.focusMultiDisplayPolicy)
        }
        let pauseFocusOnFullscreen = defaults.bool(forKey: PreferenceKey.focusPauseOnFullscreen)
        let rawSpeed = defaults.string(forKey: PreferenceKey.focusTransitionSpeed)
        let focusTransitionSpeed = FocusTransitionSpeed.fromStoredValue(rawSpeed)
        if let rawSpeed, rawSpeed != focusTransitionSpeed.rawValue {
            defaults.set(focusTransitionSpeed.rawValue, forKey: PreferenceKey.focusTransitionSpeed)
        }
        let rawTransitionStyle = defaults.string(forKey: PreferenceKey.focusTransitionStyle)
        let focusTransitionStyle: FocusTransitionStyle = if let rawTransitionStyle {
            FocusTransitionStyle.fromStoredValue(rawTransitionStyle)
        } else {
            FocusTransitionStyle.migratedStyle(fromLegacySpeed: focusTransitionSpeed)
        }
        let focusTransitionDuration: Double
        if let rawDurationObj = defaults.object(forKey: PreferenceKey.focusTransitionDuration) as? NSNumber {
            focusTransitionDuration = FocusBounds.clampedTransitionDuration(rawDurationObj.doubleValue)
        } else {
            focusTransitionDuration = FocusTransitionStyle.migratedDuration(fromLegacySpeed: focusTransitionSpeed)
        }

        let rawExcludedBundles = defaults.stringArray(forKey: PreferenceKey.focusExcludedBundleIDs) ?? []
        let focusExcludedBundleIDs = Set(
            rawExcludedBundles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let focusHotKeyEnabled = defaults.bool(forKey: PreferenceKey.focusHotKeyEnabled)
        let focusCandidateBinding = loadHotKeyBinding(
            keyCodeKey: PreferenceKey.focusHotKeyKeyCode,
            modifiersKey: PreferenceKey.focusHotKeyModifiers,
            fallback: .defaultFocusToggle
        )

        return DimmingSnapshot(
            enabled: enabled,
            intensity: DimmingBounds.clampedIntensity(rawIntensity),
            darkOnly: darkOnly,
            tint: tint,
            excludedDisplayIDs: excludedIDs,
            hotKeyEnabled: hotKeyEnabled,
            hotKeyBinding: candidateBinding,
            focusEnabled: focusEnabled,
            focusIntensity: FocusBounds.clampedIntensity(rawFocusIntensity),
            focusTint: focusTint,
            focusScope: focusScope,
            dimMenuBar: dimMenuBar,
            dimDock: dimDock,
            focusMultiDisplayPolicy: focusMultiDisplayPolicy,
            pauseFocusOnFullscreen: pauseFocusOnFullscreen,
            focusTransitionSpeed: focusTransitionSpeed,
            focusTransitionStyle: focusTransitionStyle,
            focusTransitionDuration: focusTransitionDuration,
            focusExcludedBundleIDs: focusExcludedBundleIDs,
            focusHotKeyEnabled: focusHotKeyEnabled,
            focusHotKeyBinding: focusCandidateBinding
        )
    }

    public func save(_ snapshot: DimmingSnapshot) {
        let clampedIntensity = DimmingBounds.clampedIntensity(snapshot.intensity)
        let validBinding = snapshot.hotKeyBinding.isValid ? snapshot.hotKeyBinding : .defaultToggle
        let clampedFocusIntensity = FocusBounds.clampedIntensity(snapshot.focusIntensity)
        let validFocusBinding = snapshot.focusHotKeyBinding.isValid ? snapshot.focusHotKeyBinding : .defaultFocusToggle
        let cleanedBundles = snapshot.focusExcludedBundleIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        defaults.set(snapshot.enabled, forKey: PreferenceKey.enabled)
        defaults.set(clampedIntensity, forKey: PreferenceKey.intensity)
        defaults.set(snapshot.darkOnly, forKey: PreferenceKey.darkOnly)
        defaults.set(snapshot.tint.rawValue, forKey: PreferenceKey.tint)
        defaults.set(snapshot.excludedDisplayIDs.sorted().map { NSNumber(value: $0) }, forKey: PreferenceKey.excludedDisplayIDs)
        defaults.set(snapshot.hotKeyEnabled, forKey: PreferenceKey.hotKeyEnabled)
        defaults.set(Int(validBinding.keyCode), forKey: PreferenceKey.hotKeyKeyCode)
        defaults.set(Int(validBinding.modifiers), forKey: PreferenceKey.hotKeyModifiers)
        defaults.set(snapshot.focusEnabled, forKey: PreferenceKey.focusEnabled)
        defaults.set(clampedFocusIntensity, forKey: PreferenceKey.focusIntensity)
        defaults.set(snapshot.focusTint.rawValue, forKey: PreferenceKey.focusTint)
        defaults.set(snapshot.focusScope.rawValue, forKey: PreferenceKey.focusScope)
        defaults.set(snapshot.dimMenuBar, forKey: PreferenceKey.focusDimMenuBar)
        defaults.set(snapshot.dimDock, forKey: PreferenceKey.focusDimDock)
        defaults.set(snapshot.focusMultiDisplayPolicy.rawValue, forKey: PreferenceKey.focusMultiDisplayPolicy)
        defaults.set(snapshot.pauseFocusOnFullscreen, forKey: PreferenceKey.focusPauseOnFullscreen)
        defaults.set(snapshot.focusTransitionSpeed.rawValue, forKey: PreferenceKey.focusTransitionSpeed)
        defaults.set(snapshot.focusTransitionStyle.rawValue, forKey: PreferenceKey.focusTransitionStyle)
        defaults.set(FocusBounds.clampedTransitionDuration(snapshot.focusTransitionDuration), forKey: PreferenceKey.focusTransitionDuration)
        defaults.set(cleanedBundles, forKey: PreferenceKey.focusExcludedBundleIDs)
        defaults.set(snapshot.focusHotKeyEnabled, forKey: PreferenceKey.focusHotKeyEnabled)
        defaults.set(Int(validFocusBinding.keyCode), forKey: PreferenceKey.focusHotKeyKeyCode)
        defaults.set(Int(validFocusBinding.modifiers), forKey: PreferenceKey.focusHotKeyModifiers)
    }

    private func loadHotKeyBinding(
        keyCodeKey: String,
        modifiersKey: String,
        fallback: HotKeyBinding
    ) -> HotKeyBinding {
        let keyCode = defaults.integer(forKey: keyCodeKey)
        let modifiers = defaults.integer(forKey: modifiersKey)
        if keyCode >= 0, keyCode <= Int(UInt32.max), modifiers >= 0, modifiers <= Int(UInt32.max) {
            let candidate = HotKeyBinding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
            if candidate.isValid {
                return candidate
            }
        }
        return fallback
    }

    public var didSetupLoginItem: Bool {
        get { defaults.bool(forKey: PreferenceKey.didSetupLoginItem) }
        set { defaults.set(newValue, forKey: PreferenceKey.didSetupLoginItem) }
    }
}
