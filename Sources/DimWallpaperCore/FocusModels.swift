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
    case dimInactiveScreens
    case activeScreenOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dimInactiveScreens: "副屏同步压暗"
        case .activeScreenOnly: "仅活跃屏幕"
        }
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
        case .gentle: 0.18
        case .snappy: 0.08
        case .instant: 0.0
        }
    }

    public func resolvedDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0.0 : baseDuration
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

    public init(pid: Int32, bundleIdentifier: String?, localizedName: String) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
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
        foregroundWindowFrames: [CGRect]
    ) -> FocusScreenPartition {
        guard screenFrame.width > FocusBounds.minimumStripThickness,
              screenFrame.height > FocusBounds.minimumStripThickness else {
            return FocusScreenPartition(mainRect: .zero, menuBarStripRect: nil, dockStripRects: [])
        }

        if !dimMenuBar && !dimDock {
            return FocusScreenPartition(mainRect: screenFrame, menuBarStripRect: nil, dockStripRects: [])
        }

        let clampedVisible = visibleFrame.intersection(screenFrame)
        let effectiveVisible = clampedVisible.isNull || clampedVisible.isEmpty ? screenFrame : clampedVisible

        var remaining = screenFrame
        var menuBarStrip: CGRect?

        if dimMenuBar {
            let menuBarHeight = screenFrame.maxY - effectiveVisible.maxY
            if menuBarHeight > FocusBounds.minimumStripThickness {
                menuBarStrip = CGRect(
                    x: screenFrame.minX,
                    y: effectiveVisible.maxY,
                    width: screenFrame.width,
                    height: menuBarHeight
                )
                remaining = CGRect(
                    x: screenFrame.minX,
                    y: screenFrame.minY,
                    width: screenFrame.width,
                    height: max(0, effectiveVisible.maxY - screenFrame.minY)
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
    public static let ignoredTransientBundleIDs: Set<String> = [
        "com.apple.screencaptureui",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
    ]

    public let selfPID: Int32
    public private(set) var lastExternalFrontmostApp: FocusAppIdentity?

    public init(selfPID: Int32, lastExternalFrontmostApp: FocusAppIdentity? = nil) {
        self.selfPID = selfPID
        self.lastExternalFrontmostApp = lastExternalFrontmostApp
    }

    public mutating func resolve(
        currentFrontmost: FocusAppIdentity?,
        excludedBundleIDs: Set<String>
    ) -> FocusTargetResolution {
        let candidate: FocusAppIdentity?
        if let currentFrontmost {
            let isSelf = currentFrontmost.pid == selfPID
            let isTransient = currentFrontmost.bundleIdentifier.map { Self.ignoredTransientBundleIDs.contains($0) } ?? false
            if isSelf || isTransient {
                candidate = lastExternalFrontmostApp
            } else {
                lastExternalFrontmostApp = currentFrontmost
                candidate = currentFrontmost
            }
        } else {
            candidate = lastExternalFrontmostApp
        }

        guard let target = candidate else {
            return .unavailable
        }
        if let bundleID = target.bundleIdentifier, excludedBundleIDs.contains(bundleID) {
            return .pausedByExcludedApp(target)
        }
        return .active(target)
    }
}

public struct ObservedWindowInfo: Equatable, Sendable {
    public let windowNumber: Int
    public let ownerPID: Int32
    public let layer: Int
    public let alpha: Double
    public let cgBounds: CGRect
    public let isOnScreen: Bool

    public init(
        windowNumber: Int,
        ownerPID: Int32,
        layer: Int = 0,
        alpha: Double = 1.0,
        cgBounds: CGRect,
        isOnScreen: Bool = true
    ) {
        self.windowNumber = windowNumber
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
        self.cgBounds = cgBounds
        self.isOnScreen = isOnScreen
    }

    public func isEligibleStandardWindow(excludingSelfPID selfPID: Int32) -> Bool {
        isOnScreen
            && layer == FocusWindowLevels.normalFocusLevel
            && alpha > FocusBounds.minimumWindowAlpha
            && cgBounds.width >= FocusBounds.minimumWindowDimension
            && cgBounds.height >= FocusBounds.minimumWindowDimension
            && ownerPID != selfPID
    }
}

public struct ScreenGeometry: Equatable, Sendable {
    public let displayID: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let isPrimary: Bool

    public init(displayID: UInt32, frame: CGRect, visibleFrame: CGRect, isPrimary: Bool) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isPrimary = isPrimary
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
        multiDisplayPolicy: FocusMultiDisplayPolicy
    ) -> [FocusDisplayPlan] {
        guard !screens.isEmpty else { return [] }

        let clampedAlpha = isEnabled ? FocusBounds.clampedIntensity(intensity) : 0.0
        guard isEnabled, clampedAlpha > FocusBounds.visibilityEpsilon, let targetPID else {
            return screens.map { screen in
                FocusDisplayPlan(
                    displayID: screen.displayID,
                    placement: .hidden,
                    partition: FocusScreenPartition(mainRect: screen.frame, menuBarStripRect: nil, dockStripRects: []),
                    targetAlpha: 0.0
                )
            }
        }

        let primaryHeight = Double((screens.first(where: \.isPrimary) ?? screens[0]).frame.height)
        let eligibleWindows: [(window: ObservedWindowInfo, appKitRect: CGRect)] = windows.compactMap { window in
            guard window.isEligibleStandardWindow(excludingSelfPID: selfPID) else { return nil }
            let rect = FocusCoordinateSpace.cgRectToAppKitRect(window.cgBounds, primaryScreenHeight: primaryHeight)
            return (window, rect)
        }

        let globalFrontmostTargetWindowNumber: Int? = eligibleWindows.first(where: { $0.window.ownerPID == targetPID })?.window.windowNumber

        return screens.map { screen in
            let screenWindows = eligibleWindows.filter { entry in
                windowIntersectsScreen(windowRect: entry.appKitRect, screen: screen, allScreens: screens)
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
                    placement = inactivePlacement(for: multiDisplayPolicy)
                    foregroundFrames = []
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
                    placement = inactivePlacement(for: multiDisplayPolicy)
                    foregroundFrames = []
                }
            }

            let effectiveAlpha = placement == .hidden ? 0.0 : clampedAlpha
            let partition = FocusScreenPartition.partition(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                dimMenuBar: dimMenuBar,
                dimDock: dimDock,
                foregroundWindowFrames: foregroundFrames
            )

            return FocusDisplayPlan(
                displayID: screen.displayID,
                placement: placement,
                partition: partition,
                targetAlpha: effectiveAlpha,
                foregroundWindowFrames: foregroundFrames
            )
        }
    }

    private static func inactivePlacement(for policy: FocusMultiDisplayPolicy) -> FocusWindowPlacement {
        switch policy {
        case .dimInactiveScreens: .orderFrontNormal
        case .activeScreenOnly: .hidden
        }
    }

    private static func windowIntersectsScreen(
        windowRect: CGRect,
        screen: ScreenGeometry,
        allScreens: [ScreenGeometry]
    ) -> Bool {
        let overlap = windowRect.intersection(screen.frame)
        if overlap.isNull || overlap.isEmpty {
            return false
        }
        if overlap.width >= 24 && overlap.height >= 24 {
            return true
        }
        var bestDisplayID: UInt32?
        var bestArea: CGFloat = 0
        for candidate in allScreens {
            let intersection = windowRect.intersection(candidate.frame)
            if !intersection.isNull && !intersection.isEmpty {
                let area = intersection.width * intersection.height
                if area > bestArea {
                    bestArea = area
                    bestDisplayID = candidate.displayID
                }
            }
        }
        return bestDisplayID == screen.displayID
    }
}
