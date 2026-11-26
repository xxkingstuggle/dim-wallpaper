import Foundation

public enum DimmingBounds {
    public static let minimumIntensity: Double = 0.05
    public static let maximumIntensity: Double = 0.80
    public static let defaultIntensity: Double = 0.40
    public static let visibilityEpsilon: Double = 0.005

    public static func clampedIntensity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIntensity }
        return min(max(value, minimumIntensity), maximumIntensity)
    }

    public static func percentage(for intensity: Double) -> Int {
        Int((clampedIntensity(intensity) * 100.0).rounded())
    }
}

public enum DimmingPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case gentle
    case focus
    case night
    case deep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gentle: "轻柔"
        case .focus: "专注"
        case .night: "深夜"
        case .deep: "极暗"
        }
    }

    public var symbolName: String {
        switch self {
        case .gentle: "sun.haze"
        case .focus: "sparkles"
        case .night: "moon.stars"
        case .deep: "moon.zzz"
        }
    }

    public var intensity: Double {
        switch self {
        case .gentle: 0.25
        case .focus: 0.45
        case .night: 0.65
        case .deep: 0.80
        }
    }

    public var percentage: Int {
        DimmingBounds.percentage(for: intensity)
    }

    public static func matching(intensity: Double, tolerance: Double = 0.015) -> DimmingPreset? {
        let clamped = DimmingBounds.clampedIntensity(intensity)
        return allCases.first { abs($0.intensity - clamped) <= tolerance }
    }
}

public struct TintComponents: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum DimmingTint: String, CaseIterable, Identifiable, Codable, Sendable {
    case neutral
    case warmNight
    case coolSlate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neutral: "中性黑"
        case .warmNight: "暖夜"
        case .coolSlate: "深蓝夜"
        }
    }

    public var components: TintComponents {
        switch self {
        case .neutral: TintComponents(red: 0.0, green: 0.0, blue: 0.0)
        case .warmNight: TintComponents(red: 0.11, green: 0.07, blue: 0.03)
        case .coolSlate: TintComponents(red: 0.03, green: 0.055, blue: 0.105)
        }
    }

    public var swatchComponents: TintComponents {
        switch self {
        case .neutral: TintComponents(red: 0.15, green: 0.16, blue: 0.19)
        case .warmNight: TintComponents(red: 0.62, green: 0.40, blue: 0.18)
        case .coolSlate: TintComponents(red: 0.22, green: 0.36, blue: 0.62)
        }
    }
}

public struct HotKeyBinding: Equatable, Codable, Sendable {
    public static let commandMask: UInt32 = 0x0100
    public static let shiftMask: UInt32 = 0x0200
    public static let optionMask: UInt32 = 0x0800
    public static let controlMask: UInt32 = 0x1000
    public static let supportedModifiersMask: UInt32 = commandMask | shiftMask | optionMask | controlMask

    public static let defaultToggle = HotKeyBinding(keyCode: 2, modifiers: controlMask | optionMask | commandMask)
    public static let defaultFocusToggle = HotKeyBinding(keyCode: 3, modifiers: controlMask | optionMask | commandMask)

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.supportedModifiersMask
    }

    public var isValid: Bool {
        let hasPrimaryModifier = (modifiers & (Self.commandMask | Self.optionMask | Self.controlMask)) != 0
        return hasPrimaryModifier && keyCode <= 127
    }

    public var displayLabel: String {
        var symbols = ""
        if (modifiers & Self.controlMask) != 0 { symbols += "⌃" }
        if (modifiers & Self.optionMask) != 0 { symbols += "⌥" }
        if (modifiers & Self.shiftMask) != 0 { symbols += "⇧" }
        if (modifiers & Self.commandMask) != 0 { symbols += "⌘" }
        return symbols + Self.keyLabel(for: keyCode)
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0: "A"
        case 1: "S"
        case 2: "D"
        case 3: "F"
        case 4: "H"
        case 5: "G"
        case 6: "Z"
        case 7: "X"
        case 8: "C"
        case 9: "V"
        case 11: "B"
        case 12: "Q"
        case 13: "W"
        case 14: "E"
        case 15: "R"
        case 16: "Y"
        case 17: "T"
        case 31: "O"
        case 32: "U"
        case 34: "I"
        case 35: "P"
        case 37: "L"
        case 38: "J"
        case 40: "K"
        case 45: "N"
        case 46: "M"
        default: "Key\(keyCode)"
        }
    }
}

public struct LaunchOptions: Equatable, Sendable {
    public static let defaultsSuiteEnvironmentKey = "DIM_WALLPAPER_DEFAULTS_SUITE"

    public var printStatus: Bool
    public var printStatusJSON: Bool
    public var defaultsSuiteName: String?
    public var disableLoginItemSetup: Bool
    public var allowMultipleInstances: Bool
    public var focusEnabledOverride: Bool?
    public var focusIntensityOverride: Double?
    public var dimMenuBarOverride: Bool?
    public var dimDockOverride: Bool?
    public var focusScopeOverride: FocusScope?
    public var focusMultiDisplayPolicyOverride: FocusMultiDisplayPolicy?
    public var pauseFocusOnFullscreenOverride: Bool?
    public var focusEdgeFeatherOverride: FocusEdgeFeather?

    public init(
        printStatus: Bool = false,
        printStatusJSON: Bool = false,
        defaultsSuiteName: String? = nil,
        disableLoginItemSetup: Bool = false,
        allowMultipleInstances: Bool = false,
        focusEnabledOverride: Bool? = nil,
        focusIntensityOverride: Double? = nil,
        dimMenuBarOverride: Bool? = nil,
        dimDockOverride: Bool? = nil,
        focusScopeOverride: FocusScope? = nil,
        focusMultiDisplayPolicyOverride: FocusMultiDisplayPolicy? = nil,
        pauseFocusOnFullscreenOverride: Bool? = nil,
        focusEdgeFeatherOverride: FocusEdgeFeather? = nil
    ) {
        self.printStatus = printStatus
        self.printStatusJSON = printStatusJSON
        self.defaultsSuiteName = defaultsSuiteName
        self.disableLoginItemSetup = disableLoginItemSetup
        self.allowMultipleInstances = allowMultipleInstances
        self.focusEnabledOverride = focusEnabledOverride
        self.focusIntensityOverride = focusIntensityOverride.map(FocusBounds.clampedIntensity)
        self.dimMenuBarOverride = dimMenuBarOverride
        self.dimDockOverride = dimDockOverride
        self.focusScopeOverride = focusScopeOverride
        self.focusMultiDisplayPolicyOverride = focusMultiDisplayPolicyOverride
        self.pauseFocusOnFullscreenOverride = pauseFocusOnFullscreenOverride
        self.focusEdgeFeatherOverride = focusEdgeFeatherOverride
    }

    public var hasFocusOverrides: Bool {
        focusEnabledOverride != nil
            || focusIntensityOverride != nil
            || dimMenuBarOverride != nil
            || dimDockOverride != nil
            || focusScopeOverride != nil
            || focusMultiDisplayPolicyOverride != nil
            || pauseFocusOnFullscreenOverride != nil
            || focusEdgeFeatherOverride != nil
    }

    public func applyingOverrides(to snapshot: DimmingSnapshot) -> DimmingSnapshot {
        var updated = snapshot
        if let focusEnabledOverride {
            updated.focusEnabled = focusEnabledOverride
        }
        if let focusIntensityOverride {
            updated.focusIntensity = FocusBounds.clampedIntensity(focusIntensityOverride)
        }
        if let dimMenuBarOverride {
            updated.dimMenuBar = dimMenuBarOverride
        }
        if let dimDockOverride {
            updated.dimDock = dimDockOverride
        }
        if let focusScopeOverride {
            updated.focusScope = focusScopeOverride
        }
        if let focusMultiDisplayPolicyOverride {
            updated.focusMultiDisplayPolicy = focusMultiDisplayPolicyOverride
        }
        if let pauseFocusOnFullscreenOverride {
            updated.pauseFocusOnFullscreen = pauseFocusOnFullscreenOverride
        }
        if let focusEdgeFeatherOverride {
            updated.focusEdgeFeather = focusEdgeFeatherOverride
        }
        return updated
    }

    public static func parse(arguments: [String], environment: [String: String] = [:]) -> LaunchOptions {
        var options = LaunchOptions()
        if let envSuite = environment[defaultsSuiteEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envSuite.isEmpty {
            options.defaultsSuiteName = envSuite
            options.disableLoginItemSetup = true
        }

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--status":
                options.printStatus = true
            case "--status-json":
                options.printStatusJSON = true
            case "--no-login-item":
                options.disableLoginItemSetup = true
            case "--allow-multiple-instances":
                options.allowMultipleInstances = true
            case "--defaults-suite":
                let valueIndex = index + 1
                if valueIndex < arguments.count {
                    let candidate = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        options.defaultsSuiteName = candidate
                        options.disableLoginItemSetup = true
                    }
                    index = valueIndex
                }
            case "--focus-enabled":
                if let rawValue = nextValue(after: &index, in: arguments), let parsed = parseBool(rawValue) {
                    options.focusEnabledOverride = parsed
                }
            case "--focus-intensity":
                if let rawValue = nextValue(after: &index, in: arguments), let parsed = Double(rawValue), parsed.isFinite {
                    options.focusIntensityOverride = FocusBounds.clampedIntensity(parsed)
                }
            case "--dim-menubar":
                if let rawValue = nextValue(after: &index, in: arguments), let parsed = parseBool(rawValue) {
                    options.dimMenuBarOverride = parsed
                }
            case "--dim-dock":
                if let rawValue = nextValue(after: &index, in: arguments), let parsed = parseBool(rawValue) {
                    options.dimDockOverride = parsed
                }
            case "--focus-scope":
                if let rawValue = nextValue(after: &index, in: arguments), let parsed = FocusScope(rawValue: rawValue) {
                    options.focusScopeOverride = parsed
                }
            case "--focus-policy":
                if let rawValue = nextValue(after: &index, in: arguments) {
                    options.focusMultiDisplayPolicyOverride = FocusMultiDisplayPolicy.fromStoredValue(rawValue)
                }
            case "--pause-on-fullscreen":
                if let rawValue = nextValue(after: &index, in: arguments), let parsed = parseBool(rawValue) {
                    options.pauseFocusOnFullscreenOverride = parsed
                }
            case "--focus-feather":
                if let rawValue = nextValue(after: &index, in: arguments) {
                    options.focusEdgeFeatherOverride = FocusEdgeFeather.fromStoredValue(rawValue)
                }
            default:
                if argument.hasPrefix("--defaults-suite=") {
                    let candidate = String(argument.dropFirst("--defaults-suite=".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        options.defaultsSuiteName = candidate
                        options.disableLoginItemSetup = true
                    }
                } else if argument.hasPrefix("--focus-enabled=") {
                    let raw = String(argument.dropFirst("--focus-enabled=".count))
                    if let parsed = parseBool(raw) {
                        options.focusEnabledOverride = parsed
                    }
                } else if argument.hasPrefix("--focus-intensity=") {
                    let raw = String(argument.dropFirst("--focus-intensity=".count))
                    if let parsed = Double(raw), parsed.isFinite {
                        options.focusIntensityOverride = FocusBounds.clampedIntensity(parsed)
                    }
                } else if argument.hasPrefix("--dim-menubar=") {
                    let raw = String(argument.dropFirst("--dim-menubar=".count))
                    if let parsed = parseBool(raw) {
                        options.dimMenuBarOverride = parsed
                    }
                } else if argument.hasPrefix("--dim-dock=") {
                    let raw = String(argument.dropFirst("--dim-dock=".count))
                    if let parsed = parseBool(raw) {
                        options.dimDockOverride = parsed
                    }
                } else if argument.hasPrefix("--focus-scope=") {
                    let raw = String(argument.dropFirst("--focus-scope=".count))
                    if let parsed = FocusScope(rawValue: raw) {
                        options.focusScopeOverride = parsed
                    }
                } else if argument.hasPrefix("--focus-policy=") {
                    let raw = String(argument.dropFirst("--focus-policy=".count))
                    options.focusMultiDisplayPolicyOverride = FocusMultiDisplayPolicy.fromStoredValue(raw)
                } else if argument.hasPrefix("--pause-on-fullscreen=") {
                    let raw = String(argument.dropFirst("--pause-on-fullscreen=".count))
                    if let parsed = parseBool(raw) {
                        options.pauseFocusOnFullscreenOverride = parsed
                    }
                } else if argument.hasPrefix("--focus-feather=") {
                    let raw = String(argument.dropFirst("--focus-feather=".count))
                    options.focusEdgeFeatherOverride = FocusEdgeFeather.fromStoredValue(raw)
                }
            }
            index += 1
        }
        return options
    }

    private static func nextValue(after index: inout Int, in arguments: [String]) -> String? {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else { return nil }
        index = valueIndex
        return arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "on": true
        case "false", "0", "no", "off": false
        default: nil
        }
    }
}

public enum OverlayWindowPolicy {
    public static func resolvedWindowLevel(desktopLevel: Int32, desktopIconLevel: Int32) -> Int {
        let preferred = Int(desktopLevel) + 1
        if preferred < Int(desktopIconLevel) {
            return preferred
        }
        return Int(desktopLevel)
    }

    public static func isStrictlyBetweenDesktopAndIcons(level: Int, desktopLevel: Int32, desktopIconLevel: Int32) -> Bool {
        level > Int(desktopLevel) && level < Int(desktopIconLevel)
    }
}
