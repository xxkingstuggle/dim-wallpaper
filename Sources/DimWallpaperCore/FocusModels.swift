import CoreGraphics
import Foundation

public enum FocusBounds {
    public static let minimumIntensity: Double = 0.05
    public static let maximumIntensity: Double = 0.85
    public static let defaultIntensity: Double = 0.45
    public static let visibilityEpsilon: Double = 0.005
    public static let minimumStripThickness: CGFloat = 0.5
    public static let minimumWindowDimension: CGFloat = 48.0
    public static let minimumWindowAlpha: Double = 0.01

    public static func clampedIntensity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIntensity }
        return min(max(value, minimumIntensity), maximumIntensity)
    }

    public static func percentage(for intensity: Double) -> Int {
        Int((clampedIntensity(intensity) * 100.0).rounded())
    }
}

public enum FocusPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case soft
    case balanced
    case cinema
    case deep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .soft: "轻柔"
        case .balanced: "专注"
        case .cinema: "沉浸"
        case .deep: "深邃"
        }
    }

    public var symbolName: String {
        switch self {
        case .soft: "circle.lefthalf.filled"
        case .balanced: "viewfinder"
        case .cinema: "sparkles.rectangle.stack"
        case .deep: "moon.circle.fill"
        }
    }

    public var intensity: Double {
        switch self {
        case .soft: 0.25
        case .balanced: 0.45
        case .cinema: 0.65
        case .deep: 0.85
        }
    }

    public var percentage: Int {
        FocusBounds.percentage(for: intensity)
    }

    public static func matching(intensity: Double, tolerance: Double = 0.015) -> FocusPreset? {
        let clamped = FocusBounds.clampedIntensity(intensity)
        return allCases.first { abs($0.intensity - clamped) <= tolerance }
    }
}

public enum FocusTintOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case followWallpaper
    case neutral
    case warmNight
    case coolSlate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .followWallpaper: "跟随壁纸"
        case .neutral: "中性黑"
        case .warmNight: "暖夜"
        case .coolSlate: "深蓝夜"
        }
    }

    public func resolvedTint(wallpaperTint: DimmingTint) -> DimmingTint {
        switch self {
        case .followWallpaper: wallpaperTint
        case .neutral: .neutral
        case .warmNight: .warmNight
        case .coolSlate: .coolSlate
        }
    }
}

public enum FocusScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case frontApplication
    case frontWindow

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .frontApplication: "当前前台应用"
        case .frontWindow: "仅最前单窗口"
        }
    }

    public var shortTitle: String {
        switch self {
        case .frontApplication: "前台应用"
        case .frontWindow: "最前单窗"
        }
    }
}

public enum FocusMultiDisplayPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case perDisplayFront
    case activeScreenOnly
    case dimSecondaryCompletely

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .perDisplayFront: "每屏保留最前窗口"
        case .activeScreenOnly: "仅焦点屏幕"
        case .dimSecondaryCompletely: "副屏整屏压暗"
        }
    }

    public var shortTitle: String {
        switch self {
        case .perDisplayFront: "每屏最前"
        case .activeScreenOnly: "仅焦点屏"
        case .dimSecondaryCompletely: "压暗副屏"
        }
    }

    public var detailDescription: String {
        switch self {
        case .perDisplayFront: "副屏最前窗口保持原亮，仅压暗其后杂窗与壁纸；空副屏不遮挡"
        case .activeScreenOnly: "仅当前焦点所在屏幕启用专注遮罩，其余副屏完全保持原亮"
        case .dimSecondaryCompletely: "除全屏视频外，将非焦点副屏全部压暗以屏蔽视觉干扰"
        }
    }

    public static func fromStoredValue(_ rawValue: String?) -> FocusMultiDisplayPolicy {
        guard let rawValue else { return .perDisplayFront }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "dimInactiveScreens" {
            return .perDisplayFront
        }
        return FocusMultiDisplayPolicy(rawValue: trimmed) ?? .perDisplayFront
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try? container.decode(String.self)
        self = Self.fromStoredValue(rawValue)
    }
}

public enum FocusTransitionSpeed: String, CaseIterable, Identifiable, Codable, Sendable {
    case gentle
    case snappy
    case instant

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gentle: "柔和"
        case .snappy: "灵敏"
        case .instant: "立即"
        }
    }

    public var baseDuration: Double {
        switch self {
        case .gentle: 0.11
        case .snappy: 0.06
        case .instant: 0.0
        }
    }

    public func resolvedDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0.0 : baseDuration
    }

    public func resolvedManualDuration(reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0.0 }
        switch self {
        case .instant: return 0.0
        case .snappy: return 0.06
        case .gentle: return 0.07
        }
    }
}

public enum FocusSystemBarPreset: String, CaseIterable, Identifiable, Sendable {
    case keepSystemBars
    case dimAll

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keepSystemBars: "保留菜单栏与 Dock"
        case .dimAll: "压暗全部"
        }
    }

    public static func matching(dimMenuBar: Bool, dimDock: Bool) -> FocusSystemBarPreset? {
        if !dimMenuBar && !dimDock {
            return .keepSystemBars
        }
        if dimMenuBar && dimDock {
            return .dimAll
        }
        return nil
    }
}

public struct FocusAppIdentity: Equatable, Codable, Sendable {
    public let pid: Int32
    public let bundleIdentifier: String?
    public let localizedName: String
    public let isRegularActivationPolicy: Bool

    public init(
        pid: Int32,
        bundleIdentifier: String?,
        localizedName: String,
        isRegularActivationPolicy: Bool = true
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.isRegularActivationPolicy = isRegularActivationPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pid = try container.decode(Int32.self, forKey: .pid)
        self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        self.localizedName = try container.decode(String.self, forKey: .localizedName)
        self.isRegularActivationPolicy = try container.decodeIfPresent(Bool.self, forKey: .isRegularActivationPolicy) ?? true
    }
}

public enum FocusWindowLevels {
    public static let normalFocusLevel: Int = 0

    public static func menuBarOverlayLevel(statusBarLevel: Int32, popUpMenuLevel: Int32) -> Int {
        let candidate = Int(statusBarLevel) + 1
        let upperBound = Int(popUpMenuLevel) - 1
        return min(candidate, max(Int(statusBarLevel), upperBound))
    }

    public static func dockOverlayLevel(dockLevel: Int32, mainMenuLevel: Int32) -> Int {
        let candidate = Int(dockLevel) + 1
        let upperBound = Int(mainMenuLevel) - 1
        return min(candidate, max(Int(dockLevel), upperBound))
    }
}

public enum FocusCoordinateSpace {
    public static func cgRectToAppKitRect(_ cgBounds: CGRect, primaryScreenHeight: Double) -> CGRect {
        let appKitOriginY = CGFloat(primaryScreenHeight) - cgBounds.maxY
        return CGRect(
            x: cgBounds.origin.x,
            y: appKitOriginY,
            width: cgBounds.width,
            height: cgBounds.height
        )
    }
}

public struct FocusScreenPartition: Equatable, Sendable {
    public let mainRect: CGRect
    public let menuBarStripRect: CGRect?
    public let dockStripRects: [CGRect]

    public init(mainRect: CGRect, menuBarStripRect: CGRect?, dockStripRects: [CGRect]) {
        self.mainRect = mainRect
        self.menuBarStripRect = menuBarStripRect
        self.dockStripRects = dockStripRects
    }

    public var allRects: [CGRect] {
        var rects: [CGRect] = []
        if mainRect.width > FocusBounds.minimumStripThickness,
           mainRect.height > FocusBounds.minimumStripThickness {
            rects.append(mainRect)
        }
        if let menuBarStripRect,
           menuBarStripRect.width > FocusBounds.minimumStripThickness,
           menuBarStripRect.height > FocusBounds.minimumStripThickness {
            rects.append(menuBarStripRect)
        }
        for strip in dockStripRects where strip.width > FocusBounds.minimumStripThickness && strip.height > FocusBounds.minimumStripThickness {
            rects.append(strip)
        }
        return rects
    }

    public static func partition(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        dimMenuBar: Bool,
        dimDock: Bool,
        anchorWindowFrame: CGRect? = nil
    ) -> FocusScreenPartition {
        let frames = anchorWindowFrame.map { [$0] } ?? []
        return partition(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            dimMenuBar: dimMenuBar,
            dimDock: dimDock,
            foregroundWindowFrames: frames
        )
    }

    public static func partition(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        dimMenuBar: Bool,
        dimDock: Bool,
        foregroundWindowFrames: [CGRect],
        safeAreaTopInset: CGFloat = 0,
        systemMenuBarBottomY: CGFloat? = nil
    ) -> FocusScreenPartition {
        guard screenFrame.width > FocusBounds.minimumStripThickness,
              screenFrame.height > FocusBounds.minimumStripThickness else {
            return FocusScreenPartition(mainRect: .zero, menuBarStripRect: nil, dockStripRects: [])
        }

        let clampedVisible = visibleFrame.intersection(screenFrame)
        let effectiveVisible = clampedVisible.isNull || clampedVisible.isEmpty ? screenFrame : clampedVisible
        let menuBarBottomY = resolvedMenuBarBottomY(
            screenFrame: screenFrame,
            effectiveVisible: effectiveVisible,
            safeAreaTopInset: safeAreaTopInset,
            systemMenuBarBottomY: systemMenuBarBottomY
        )
        let menuBarHeight = max(0, screenFrame.maxY - menuBarBottomY)

        var remaining = screenFrame
        var menuBarStrip: CGRect?

        if menuBarHeight > FocusBounds.minimumStripThickness {
            remaining = CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: max(0, menuBarBottomY - screenFrame.minY)
            )
            if dimMenuBar {
                menuBarStrip = CGRect(
                    x: screenFrame.minX,
                    y: menuBarBottomY,
                    width: screenFrame.width,
                    height: menuBarHeight
                )
            }
        }

        var dockStrips: [CGRect] = []
        if dimDock, remaining.width > FocusBounds.minimumStripThickness, remaining.height > FocusBounds.minimumStripThickness {
            let bottomInset = max(0, effectiveVisible.minY - remaining.minY)
            let leftInset = max(0, effectiveVisible.minX - remaining.minX)
            let rightInset = max(0, remaining.maxX - effectiveVisible.maxX)

            let rawDockRect: CGRect?
            if bottomInset > FocusBounds.minimumStripThickness,
               bottomInset >= leftInset,
               bottomInset >= rightInset {
                rawDockRect = CGRect(
                    x: remaining.minX,
                    y: remaining.minY,
                    width: remaining.width,
                    height: bottomInset
                )
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + bottomInset,
                    width: remaining.width,
                    height: max(0, remaining.height - bottomInset)
                )
            } else if leftInset > FocusBounds.minimumStripThickness,
                      leftInset >= rightInset {
                rawDockRect = CGRect(
                    x: remaining.minX,
                    y: remaining.minY,
                    width: leftInset,
                    height: remaining.height
                )
                remaining = CGRect(
                    x: remaining.minX + leftInset,
                    y: remaining.minY,
                    width: max(0, remaining.width - leftInset),
                    height: remaining.height
                )
            } else if rightInset > FocusBounds.minimumStripThickness {
                rawDockRect = CGRect(
                    x: remaining.maxX - rightInset,
                    y: remaining.minY,
                    width: rightInset,
                    height: remaining.height
                )
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY,
                    width: max(0, remaining.width - rightInset),
                    height: remaining.height
                )
            } else {
                rawDockRect = nil
            }

            if let rawDockRect {
                var pieces = [rawDockRect]
                for foregroundFrame in foregroundWindowFrames {
                    pieces = pieces.flatMap { subtract(cutout: foregroundFrame, from: $0) }
                }
                dockStrips = pieces.sorted { lhs, rhs in
                    if abs(lhs.minX - rhs.minX) > 0.5 {
                        return lhs.minX < rhs.minX
                    }
                    return lhs.minY < rhs.minY
                }
            }
        }

        return FocusScreenPartition(
            mainRect: remaining,
            menuBarStripRect: menuBarStrip,
            dockStripRects: dockStrips
        )
    }

    public static func resolvedMenuBarBottomY(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTopInset: CGFloat = 0,
        systemMenuBarBottomY: CGFloat? = nil
    ) -> CGFloat {
        let clampedVisible = visibleFrame.intersection(screenFrame)
        let effectiveVisible = clampedVisible.isNull || clampedVisible.isEmpty ? screenFrame : clampedVisible
        return resolvedMenuBarBottomY(
            screenFrame: screenFrame,
            effectiveVisible: effectiveVisible,
            safeAreaTopInset: safeAreaTopInset,
            systemMenuBarBottomY: systemMenuBarBottomY
        )
    }

    private static func resolvedMenuBarBottomY(
        screenFrame: CGRect,
        effectiveVisible: CGRect,
        safeAreaTopInset: CGFloat,
        systemMenuBarBottomY: CGFloat?
    ) -> CGFloat {
        var bottomY = effectiveVisible.maxY
        if safeAreaTopInset.isFinite && safeAreaTopInset > FocusBounds.minimumStripThickness {
            bottomY = min(bottomY, screenFrame.maxY - safeAreaTopInset)
        }
        if let systemMenuBarBottomY, systemMenuBarBottomY.isFinite {
            let clampedSystemBottom = min(max(systemMenuBarBottomY, screenFrame.minY), screenFrame.maxY)
            bottomY = min(bottomY, clampedSystemBottom)
        }
        return min(max(bottomY, screenFrame.minY), screenFrame.maxY)
    }

    public static func subtract(cutout: CGRect, from source: CGRect) -> [CGRect] {
        let overlap = source.intersection(cutout)
        if overlap.isNull || overlap.isEmpty
            || overlap.width <= FocusBounds.minimumStripThickness
            || overlap.height <= FocusBounds.minimumStripThickness {
            return [source]
        }

        var result: [CGRect] = []

        let leftWidth = overlap.minX - source.minX
        if leftWidth > FocusBounds.minimumStripThickness {
            result.append(CGRect(x: source.minX, y: source.minY, width: leftWidth, height: source.height))
        }

        let rightWidth = source.maxX - overlap.maxX
        if rightWidth > FocusBounds.minimumStripThickness {
            result.append(CGRect(x: overlap.maxX, y: source.minY, width: rightWidth, height: source.height))
        }

        let bottomHeight = overlap.minY - source.minY
        if bottomHeight > FocusBounds.minimumStripThickness {
            result.append(CGRect(x: overlap.minX, y: source.minY, width: overlap.width, height: bottomHeight))
        }

        let topHeight = source.maxY - overlap.maxY
        if topHeight > FocusBounds.minimumStripThickness {
            result.append(CGRect(x: overlap.minX, y: overlap.maxY, width: overlap.width, height: topHeight))
        }

        return result
    }
}

public enum FocusTargetResolution: Equatable, Sendable {
    case active(FocusAppIdentity)
    case pausedByExcludedApp(FocusAppIdentity)
    case unavailable
}

public struct FocusTargetResolver: Equatable, Sendable {
    public static let desktopShellBundleIDs: Set<String> = [
        "com.apple.WindowManager",
        "com.apple.dock",
    ]

    public static let ignoredTransientBundleIDs: Set<String> = [
        "com.apple.screencaptureui",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.UserNotificationCenter",
        "com.apple.SecurityAgent",
        "com.apple.CoreServicesUIAgent",
        "com.apple.OSDUIHelper",
        "com.apple.loginwindow",
    ]

    public static let systemShellBundleIDs: Set<String> = ignoredTransientBundleIDs
        .union(desktopShellBundleIDs)
        .union(["com.apple.systemuiserver"])

    public static let systemShellOwnerNames: Set<String> = [
        "WindowManager",
        "Dock",
        "Control Center",
        "Notification Center",
        "Spotlight",
        "Window Server",
        "SystemUIServer",
    ]

    public let selfPID: Int32
    public private(set) var lastExternalFrontmostApp: FocusAppIdentity?
    public private(set) var isInDesktopState: Bool

    public init(
        selfPID: Int32,
        lastExternalFrontmostApp: FocusAppIdentity? = nil,
        isInDesktopState: Bool = false
    ) {
        self.selfPID = selfPID
        self.lastExternalFrontmostApp = lastExternalFrontmostApp
        self.isInDesktopState = isInDesktopState
    }

    public mutating func recordFrontmostAppFast(_ currentFrontmost: FocusAppIdentity?) {
        guard let currentFrontmost else { return }
        if currentFrontmost.pid == selfPID {
            return
        }
        if let bundleID = currentFrontmost.bundleIdentifier {
            if Self.desktopShellBundleIDs.contains(bundleID) {
                isInDesktopState = true
                lastExternalFrontmostApp = nil
                return
            }
            if Self.ignoredTransientBundleIDs.contains(bundleID) {
                return
            }
        }
        if currentFrontmost.isRegularActivationPolicy {
            isInDesktopState = false
            lastExternalFrontmostApp = currentFrontmost
        }
    }

    public mutating func resolve(
        currentFrontmost: FocusAppIdentity?,
        excludedBundleIDs: Set<String>,
        observedWindows: [ObservedWindowInfo] = [],
        screens: [ScreenGeometry] = [],
        fallbackAppProvider: ((Int32) -> FocusAppIdentity?)? = nil
    ) -> FocusTargetResolution {
        let candidateWindows = FocusWindowOrderPlanner.filteredActiveStageWindows(
            windows: observedWindows,
            screens: screens,
            excludingSelfPID: selfPID
        )

        var candidate: FocusAppIdentity?
        if let currentFrontmost {
            let bundleID = currentFrontmost.bundleIdentifier
            if let bundleID, Self.desktopShellBundleIDs.contains(bundleID) {
                isInDesktopState = true
                lastExternalFrontmostApp = nil
                return .unavailable
            }

            let isSelf = currentFrontmost.pid == selfPID
            let isTransient = bundleID.map { Self.ignoredTransientBundleIDs.contains($0) } ?? false
            let isNonRegularWithoutStandardWindow = !currentFrontmost.isRegularActivationPolicy
                && !candidateWindows.contains {
                    $0.ownerPID == currentFrontmost.pid
                }
            if isSelf || isTransient || isNonRegularWithoutStandardWindow {
                if isInDesktopState {
                    return .unavailable
                }
                candidate = lastExternalFrontmostApp
            } else {
                isInDesktopState = false
                lastExternalFrontmostApp = currentFrontmost
                candidate = currentFrontmost
            }
        } else {
            if isInDesktopState {
                return .unavailable
            }
            candidate = lastExternalFrontmostApp
        }

        if candidate == nil, !isInDesktopState, !candidateWindows.isEmpty {
            if let fallback = resolveColdStartFallback(
                candidateWindows: candidateWindows,
                fallbackAppProvider: fallbackAppProvider
            ) {
                lastExternalFrontmostApp = fallback
                candidate = fallback
            }
        }

        guard let target = candidate else {
            return .unavailable
        }
        if let bundleID = target.bundleIdentifier, excludedBundleIDs.contains(bundleID) {
            return .pausedByExcludedApp(target)
        }
        return .active(target)
    }

    private func resolveColdStartFallback(
        candidateWindows: [ObservedWindowInfo],
        fallbackAppProvider: ((Int32) -> FocusAppIdentity?)?
    ) -> FocusAppIdentity? {
        var seenPIDs = Set<Int32>()
        for window in candidateWindows {
            guard seenPIDs.insert(window.ownerPID).inserted else { continue }

            if let fallbackAppProvider {
                guard let resolved = fallbackAppProvider(window.ownerPID) else { continue }
                let isSystemShell = resolved.bundleIdentifier.map { Self.systemShellBundleIDs.contains($0) } ?? false
                if isSystemShell || resolved.pid == selfPID {
                    continue
                }
                return resolved
            }

            return FocusAppIdentity(
                pid: window.ownerPID,
                bundleIdentifier: nil,
                localizedName: "PID \(window.ownerPID)",
                isRegularActivationPolicy: true
            )
        }
        return nil
    }
}

public struct ObservedWindowInfo: Equatable, Sendable {
    public let windowNumber: Int
    public let ownerPID: Int32
    public let layer: Int
    public let alpha: Double
    public let cgBounds: CGRect
    public let isOnScreen: Bool
    public let ownerName: String?
    public let ownerBundleIdentifier: String?

    public init(
        windowNumber: Int,
        ownerPID: Int32,
        layer: Int = 0,
        alpha: Double = 1.0,
        cgBounds: CGRect,
        isOnScreen: Bool = true,
        ownerName: String? = nil,
        ownerBundleIdentifier: String? = nil
    ) {
        self.windowNumber = windowNumber
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
        self.cgBounds = cgBounds
        self.isOnScreen = isOnScreen
        self.ownerName = ownerName
        self.ownerBundleIdentifier = ownerBundleIdentifier
    }

    public var isWindowManagerLayerZeroWindow: Bool {
        isOnScreen
            && layer == FocusWindowLevels.normalFocusLevel
            && (ownerBundleIdentifier == "com.apple.WindowManager" || ownerName == "WindowManager")
    }

    public var isSystemShellWindow: Bool {
        if let ownerBundleIdentifier, FocusTargetResolver.systemShellBundleIDs.contains(ownerBundleIdentifier) {
            return true
        }
        if let ownerName, FocusTargetResolver.systemShellOwnerNames.contains(ownerName) {
            return true
        }
        return false
    }

    public func isEligibleStandardWindow(excludingSelfPID selfPID: Int32) -> Bool {
        isOnScreen
            && layer == FocusWindowLevels.normalFocusLevel
            && alpha > FocusBounds.minimumWindowAlpha
            && cgBounds.width >= FocusBounds.minimumWindowDimension
            && cgBounds.height >= FocusBounds.minimumWindowDimension
            && ownerPID != selfPID
            && !isSystemShellWindow
    }
}

public struct ScreenGeometry: Equatable, Sendable {
    public let displayID: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let isPrimary: Bool
    public let safeAreaTopInset: CGFloat
    public let systemMenuBarBottomY: CGFloat?

    public init(
        displayID: UInt32,
        frame: CGRect,
        visibleFrame: CGRect,
        isPrimary: Bool,
        safeAreaTopInset: CGFloat = 0,
        systemMenuBarBottomY: CGFloat? = nil
    ) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isPrimary = isPrimary
        self.safeAreaTopInset = safeAreaTopInset
        self.systemMenuBarBottomY = systemMenuBarBottomY
    }
}

public enum FocusWindowPlacement: Equatable, Sendable {
    case hidden
    case orderBelow(windowNumber: Int)
    case orderFrontNormal
}

public struct FocusDisplayPlan: Equatable, Sendable {
    public let displayID: UInt32
    public let placement: FocusWindowPlacement
    public let partition: FocusScreenPartition
    public let targetAlpha: Double
    public let foregroundWindowFrames: [CGRect]

    public init(
        displayID: UInt32,
        placement: FocusWindowPlacement,
        partition: FocusScreenPartition,
        targetAlpha: Double,
        foregroundWindowFrames: [CGRect] = []
    ) {
        self.displayID = displayID
        self.placement = placement
        self.partition = partition
        self.targetAlpha = targetAlpha
        self.foregroundWindowFrames = foregroundWindowFrames
    }

    public var shouldShow: Bool {
        placement != .hidden && targetAlpha > FocusBounds.visibilityEpsilon
    }
}

public enum FocusWindowOrderPlanner {
    public static let minimumStageIntersectionDimension: CGFloat = 80.0
    public static let minimumStageCoverageRatio: CGFloat = 0.45
    public static let stageManagerThumbnailOverlapRatio: CGFloat = 0.65
    public static let stageManagerEdgeTolerance: CGFloat = 6.0

    public static func isStageManagerThumbnail(
        _ window: ObservedWindowInfo,
        windowManagerRects: [CGRect]
    ) -> Bool {
        let windowArea = window.cgBounds.width * window.cgBounds.height
        guard windowArea > 0, !windowManagerRects.isEmpty else { return false }
        for wmRect in windowManagerRects {
            let edgesMatch = abs(window.cgBounds.minX - wmRect.minX) <= stageManagerEdgeTolerance
                && abs(window.cgBounds.maxX - wmRect.maxX) <= stageManagerEdgeTolerance
                && abs(window.cgBounds.minY - wmRect.minY) <= stageManagerEdgeTolerance
                && abs(window.cgBounds.maxY - wmRect.maxY) <= stageManagerEdgeTolerance
            if edgesMatch {
                return true
            }
            let overlap = window.cgBounds.intersection(wmRect)
            if !overlap.isNull && !overlap.isEmpty {
                let overlapArea = overlap.width * overlap.height
                if (overlapArea / windowArea) >= stageManagerThumbnailOverlapRatio {
                    return true
                }
            }
        }
        return false
    }

    public static func isActiveStageWindowOnScreen(
        windowRect: CGRect,
        screenFrame: CGRect
    ) -> Bool {
        let overlap = windowRect.intersection(screenFrame)
        guard !overlap.isNull && !overlap.isEmpty else { return false }
        guard overlap.width >= minimumStageIntersectionDimension,
              overlap.height >= minimumStageIntersectionDimension else {
            return false
        }
        let windowArea = windowRect.width * windowRect.height
        let screenArea = screenFrame.width * screenFrame.height
        let referenceArea = min(windowArea, screenArea)
        guard referenceArea > 0 else { return false }
        return ((overlap.width * overlap.height) / referenceArea) >= minimumStageCoverageRatio
    }

    public static func filteredActiveStageWindows(
        windows: [ObservedWindowInfo],
        screens: [ScreenGeometry],
        excludingSelfPID selfPID: Int32
    ) -> [ObservedWindowInfo] {
        let windowManagerRects = windows
            .filter(\.isWindowManagerLayerZeroWindow)
            .map(\.cgBounds)
        let baseCandidates = windows.filter { window in
            window.isEligibleStandardWindow(excludingSelfPID: selfPID)
                && !isStageManagerThumbnail(window, windowManagerRects: windowManagerRects)
        }
        guard !screens.isEmpty else {
            return baseCandidates
        }
        let primaryHeight = Double((screens.first(where: \.isPrimary) ?? screens[0]).frame.height)
        return baseCandidates.filter { window in
            let appKitRect = FocusCoordinateSpace.cgRectToAppKitRect(window.cgBounds, primaryScreenHeight: primaryHeight)
            return screens.contains { screen in
                isActiveStageWindowOnScreen(windowRect: appKitRect, screenFrame: screen.frame)
            }
        }
    }

    public static func plan(
        screens: [ScreenGeometry],
        windows: [ObservedWindowInfo],
        targetPID: Int32?,
        selfPID: Int32,
        isEnabled: Bool,
        intensity: Double,
        scope: FocusScope,
        dimMenuBar: Bool,
        dimDock: Bool,
        multiDisplayPolicy: FocusMultiDisplayPolicy,
        excludedDisplayIDs: Set<UInt32> = [],
        pauseFocusOnFullscreen: Bool = true,
        excludedBundleIDs: Set<String> = []
    ) -> [FocusDisplayPlan] {
        guard !screens.isEmpty else { return [] }

        let primaryHeight = Double((screens.first(where: \.isPrimary) ?? screens[0]).frame.height)
        let systemMenuBarBottomByDisplay = resolvedSystemMenuBarBottomByDisplay(
            screens: screens,
            windows: windows,
            primaryScreenHeight: primaryHeight
        )
        let hasObservedSystemMenuBar = !systemMenuBarBottomByDisplay.isEmpty
        let normalizedExcludedBundleIDs = Set(
            excludedBundleIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        func makeHiddenPlan(for screen: ScreenGeometry) -> FocusDisplayPlan {
            let partition = FocusScreenPartition.partition(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                dimMenuBar: false,
                dimDock: false,
                foregroundWindowFrames: [],
                safeAreaTopInset: screen.safeAreaTopInset,
                systemMenuBarBottomY: systemMenuBarBottomByDisplay[screen.displayID]
            )
            return FocusDisplayPlan(
                displayID: screen.displayID,
                placement: .hidden,
                partition: partition,
                targetAlpha: 0.0,
                foregroundWindowFrames: []
            )
        }

        let clampedAlpha = isEnabled ? FocusBounds.clampedIntensity(intensity) : 0.0
        guard isEnabled, clampedAlpha > FocusBounds.visibilityEpsilon, let targetPID else {
            return screens.map(makeHiddenPlan)
        }

        let activeStageWindows = filteredActiveStageWindows(
            windows: windows,
            screens: screens,
            excludingSelfPID: selfPID
        )
        let eligibleWindows: [(window: ObservedWindowInfo, appKitRect: CGRect)] = activeStageWindows.map { window in
            (window, FocusCoordinateSpace.cgRectToAppKitRect(window.cgBounds, primaryScreenHeight: primaryHeight))
        }

        let targetHasActiveStageWindow = eligibleWindows.contains { $0.window.ownerPID == targetPID }
        guard targetHasActiveStageWindow else {
            return screens.map(makeHiddenPlan)
        }

        let globalFrontmostTargetWindowNumber: Int? = eligibleWindows.first(where: { $0.window.ownerPID == targetPID })?.window.windowNumber

        let candidatePlans: [FocusDisplayPlan] = screens.map { screen in
            if excludedDisplayIDs.contains(screen.displayID) {
                return makeHiddenPlan(for: screen)
            }

            let screenWindows = eligibleWindows.filter { entry in
                isActiveStageWindowOnScreen(windowRect: entry.appKitRect, screenFrame: screen.frame)
            }

            if pauseFocusOnFullscreen,
               isScreenShowingFullscreenContent(
                   screen: screen,
                   screenWindows: screenWindows,
                   allWindows: windows,
                   selfPID: selfPID,
                   primaryScreenHeight: primaryHeight,
                   hasObservedSystemMenuBarOnAnyScreen: hasObservedSystemMenuBar,
                   screenHasSystemMenuBar: systemMenuBarBottomByDisplay[screen.displayID] != nil,
                   systemMenuBarBottomY: systemMenuBarBottomByDisplay[screen.displayID]
               ) {
                return makeHiddenPlan(for: screen)
            }

            let placement: FocusWindowPlacement
            let foregroundFrames: [CGRect]

            switch scope {
            case .frontWindow:
                if let topWindowNumber = globalFrontmostTargetWindowNumber,
                   let topMatch = screenWindows.first(where: { $0.window.windowNumber == topWindowNumber }),
                   screenWindows.first?.window.windowNumber == topWindowNumber {
                    placement = .orderBelow(windowNumber: topMatch.window.windowNumber)
                    foregroundFrames = [topMatch.appKitRect]
                } else {
                    let secondary = secondaryDisplayPlacement(
                        screenWindows: screenWindows,
                        scope: scope,
                        policy: multiDisplayPolicy,
                        normalizedExcludedBundleIDs: normalizedExcludedBundleIDs
                    )
                    placement = secondary.placement
                    foregroundFrames = secondary.foregroundFrames
                }

            case .frontApplication:
                if let firstOnScreen = screenWindows.first, firstOnScreen.window.ownerPID == targetPID {
                    var anchorWindowNumber = firstOnScreen.window.windowNumber
                    var collectedFrames: [CGRect] = []
                    for entry in screenWindows {
                        guard entry.window.ownerPID == targetPID else { break }
                        anchorWindowNumber = entry.window.windowNumber
                        collectedFrames.append(entry.appKitRect)
                    }
                    placement = .orderBelow(windowNumber: anchorWindowNumber)
                    foregroundFrames = collectedFrames
                } else {
                    let secondary = secondaryDisplayPlacement(
                        screenWindows: screenWindows,
                        scope: scope,
                        policy: multiDisplayPolicy,
                        normalizedExcludedBundleIDs: normalizedExcludedBundleIDs
                    )
                    placement = secondary.placement
                    foregroundFrames = secondary.foregroundFrames
                }
            }

            let effectiveAlpha = placement == .hidden ? 0.0 : clampedAlpha
            let partition = FocusScreenPartition.partition(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                dimMenuBar: dimMenuBar,
                dimDock: dimDock,
                foregroundWindowFrames: foregroundFrames,
                safeAreaTopInset: screen.safeAreaTopInset,
                systemMenuBarBottomY: systemMenuBarBottomByDisplay[screen.displayID]
            )

            return FocusDisplayPlan(
                displayID: screen.displayID,
                placement: placement,
                partition: partition,
                targetAlpha: effectiveAlpha,
                foregroundWindowFrames: foregroundFrames
            )
        }

        return candidatePlans
    }

    public static func isScreenShowingFullscreenContent(
        screen: ScreenGeometry,
        screenWindows: [(window: ObservedWindowInfo, appKitRect: CGRect)],
        allWindows: [ObservedWindowInfo] = [],
        selfPID: Int32 = -1,
        primaryScreenHeight: Double = 0,
        hasObservedSystemMenuBarOnAnyScreen: Bool = false,
        screenHasSystemMenuBar: Bool = true,
        systemMenuBarBottomY: CGFloat? = nil
    ) -> Bool {
        guard screen.frame.width > 1, screen.frame.height > 1 else { return false }

        let clampedVisible = screen.visibleFrame.intersection(screen.frame)
        let effectiveVisible = (clampedVisible.isNull || clampedVisible.isEmpty) ? screen.frame : clampedVisible
        let menuBarBottomY = FocusScreenPartition.resolvedMenuBarBottomY(
            screenFrame: screen.frame,
            visibleFrame: effectiveVisible,
            safeAreaTopInset: screen.safeAreaTopInset,
            systemMenuBarBottomY: systemMenuBarBottomY
        )
        let menuBarHeight = max(0, screen.frame.maxY - menuBarBottomY)
        let menuBarAutoHidden = screen.visibleFrame.height >= screen.frame.height - 2.0
            && screen.safeAreaTopInset <= 2.0
            && !screenHasSystemMenuBar
        let hasVisibleMenuBar = screenHasSystemMenuBar
            && menuBarHeight > FocusBounds.minimumStripThickness
            && !menuBarAutoHidden
        let screenArea = screen.frame.width * screen.frame.height
        let visibleArea = effectiveVisible.width * effectiveVisible.height
        let effectivePrimaryHeight = primaryScreenHeight > 0 ? primaryScreenHeight : Double(screen.frame.height)

        for window in allWindows {
            guard window.isOnScreen,
                  window.layer >= 0,
                  window.alpha > 0.1,
                  window.ownerPID != selfPID,
                  !window.isSystemShellWindow else {
                continue
            }
            let appKitRect = FocusCoordinateSpace.cgRectToAppKitRect(
                window.cgBounds,
                primaryScreenHeight: effectivePrimaryHeight
            )
            let frameOverlap = appKitRect.intersection(screen.frame)
            guard !frameOverlap.isNull && !frameOverlap.isEmpty else { continue }
            let widthRatio = frameOverlap.width / screen.frame.width
            let heightRatio = frameOverlap.height / screen.frame.height
            if widthRatio >= 0.98 && heightRatio >= 0.98 {
                if window.layer > 0 || !hasVisibleMenuBar || frameOverlap.maxY > menuBarBottomY + 2.0 {
                    return true
                }
            }
        }

        guard let topEntry = screenWindows.first else { return false }
        let topPID = topEntry.window.ownerPID
        var leadingOwnerEntries: [(window: ObservedWindowInfo, appKitRect: CGRect)] = []
        for entry in screenWindows {
            guard entry.window.ownerPID == topPID else { break }
            leadingOwnerEntries.append(entry)
        }

        for entry in leadingOwnerEntries {
            let frameOverlap = entry.appKitRect.intersection(screen.frame)
            if !frameOverlap.isNull && !frameOverlap.isEmpty {
                let widthRatio = frameOverlap.width / screen.frame.width
                let heightRatio = frameOverlap.height / screen.frame.height
                let frameAreaRatio = (frameOverlap.width * frameOverlap.height) / screenArea

                if hasVisibleMenuBar {
                    let invadesMenuBar = frameOverlap.maxY > menuBarBottomY + 2.0
                    if invadesMenuBar && widthRatio >= 0.95 && heightRatio >= 0.95 {
                        return true
                    }
                } else {
                    if widthRatio >= 0.98 && heightRatio >= 0.98 {
                        return true
                    }
                    if menuBarAutoHidden && frameAreaRatio >= 0.98 {
                        return true
                    }
                }
            }

            if !screenHasSystemMenuBar && !menuBarAutoHidden, visibleArea > 1 {
                let visibleOverlap = entry.appKitRect.intersection(effectiveVisible)
                if !visibleOverlap.isNull && !visibleOverlap.isEmpty {
                    let visibleWidthRatio = visibleOverlap.width / effectiveVisible.width
                    let visibleHeightRatio = visibleOverlap.height / effectiveVisible.height
                    if visibleWidthRatio >= 0.96 && visibleHeightRatio >= 0.96 {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func resolvedSystemMenuBarBottomByDisplay(
        screens: [ScreenGeometry],
        windows: [ObservedWindowInfo],
        primaryScreenHeight: Double
    ) -> [UInt32: CGFloat] {
        var result: [UInt32: CGFloat] = [:]
        for screen in screens {
            if let explicit = screen.systemMenuBarBottomY, explicit.isFinite {
                result[screen.displayID] = explicit
            }
        }
        let mainMenuLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
        let statusLayerMinusOne = Int(CGWindowLevelForKey(.statusWindow)) - 1

        for window in windows {
            guard window.isOnScreen,
                  window.layer == mainMenuLayer || window.layer == statusLayerMinusOne else {
                continue
            }
            if let ownerName = window.ownerName, ownerName != "Window Server" && ownerName != "SystemUIServer" {
                continue
            }
            let appKitRect = FocusCoordinateSpace.cgRectToAppKitRect(window.cgBounds, primaryScreenHeight: primaryScreenHeight)
            guard appKitRect.height > FocusBounds.minimumStripThickness, appKitRect.height <= 80.0 else {
                continue
            }
            for screen in screens {
                let horizontalOverlap = min(appKitRect.maxX, screen.frame.maxX) - max(appKitRect.minX, screen.frame.minX)
                guard horizontalOverlap >= screen.frame.width * 0.5 else { continue }
                guard appKitRect.maxY >= screen.frame.maxY - 2.0,
                      appKitRect.minY < screen.frame.maxY - FocusBounds.minimumStripThickness else {
                    continue
                }
                let clampedBottom = min(max(appKitRect.minY, screen.frame.minY), screen.frame.maxY)
                if let existing = result[screen.displayID] {
                    result[screen.displayID] = min(existing, clampedBottom)
                } else {
                    result[screen.displayID] = clampedBottom
                }
            }
        }
        return result
    }

    private static func secondaryDisplayPlacement(
        screenWindows: [(window: ObservedWindowInfo, appKitRect: CGRect)],
        scope: FocusScope,
        policy: FocusMultiDisplayPolicy,
        normalizedExcludedBundleIDs: Set<String>
    ) -> (placement: FocusWindowPlacement, foregroundFrames: [CGRect]) {
        switch policy {
        case .perDisplayFront:
            guard let secondaryTop = screenWindows.first else {
                return (.hidden, [])
            }
            if let bundleID = secondaryTop.window.ownerBundleIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               !bundleID.isEmpty,
               normalizedExcludedBundleIDs.contains(bundleID) {
                return (.hidden, [])
            }
            switch scope {
            case .frontWindow:
                return (.orderBelow(windowNumber: secondaryTop.window.windowNumber), [secondaryTop.appKitRect])
            case .frontApplication:
                let secondaryPID = secondaryTop.window.ownerPID
                var anchorWindowNumber = secondaryTop.window.windowNumber
                var collectedFrames: [CGRect] = []
                for entry in screenWindows {
                    guard entry.window.ownerPID == secondaryPID else { break }
                    anchorWindowNumber = entry.window.windowNumber
                    collectedFrames.append(entry.appKitRect)
                }
                return (.orderBelow(windowNumber: anchorWindowNumber), collectedFrames)
            }
        case .activeScreenOnly:
            return (.hidden, [])
        case .dimSecondaryCompletely:
            return (.orderFrontNormal, [])
        }
    }
}
