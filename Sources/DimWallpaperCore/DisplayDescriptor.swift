import Foundation

public struct DisplayDescriptor: Identifiable, Equatable, Codable, Sendable {
    public let id: UInt32
    public let name: String
    public let logicalWidth: Int
    public let logicalHeight: Int
    public let scaleFactor: Double
    public let isBuiltIn: Bool
    public let isMain: Bool

    public init(
        id: UInt32,
        name: String,
        logicalWidth: Int,
        logicalHeight: Int,
        scaleFactor: Double,
        isBuiltIn: Bool,
        isMain: Bool
    ) {
        self.id = id
        self.name = name
        self.logicalWidth = max(0, logicalWidth)
        self.logicalHeight = max(0, logicalHeight)
        self.scaleFactor = scaleFactor.isFinite && scaleFactor > 0 ? scaleFactor : 1.0
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
    }

    public var resolutionLabel: String {
        let roundedScale = scaleFactor.rounded()
        let scaleText: String
        if abs(scaleFactor - roundedScale) < 0.01 {
            scaleText = "\(Int(roundedScale))x"
        } else {
            scaleText = String(format: "%.1fx", scaleFactor)
        }
        return "\(logicalWidth)×\(logicalHeight) · \(scaleText)"
    }
}

public struct DisplayOverlayDecision: Equatable, Sendable {
    public let displayID: UInt32
    public let isExcluded: Bool
    public let targetAlpha: Double

    public init(displayID: UInt32, isExcluded: Bool, targetAlpha: Double) {
        self.displayID = displayID
        self.isExcluded = isExcluded
        self.targetAlpha = targetAlpha
    }

    public var shouldShowWindow: Bool {
        targetAlpha > DimmingBounds.visibilityEpsilon
    }
}
