import CoreGraphics
import Foundation

public enum FocusTransitionStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case fluidEase
    case linear
    case organicBreath
    case waveTide
    case inkBloom
    case velvetCurtain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fluidEase: "丝滑缓动"
        case .linear: "匀速线性"
        case .organicBreath: "呼吸阻尼"
        case .waveTide: "海浪漫延"
        case .inkBloom: "水墨晕染"
        case .velvetCurtain: "天幕垂落"
        }
    }

    public var shortTag: String {
        switch self {
        case .fluidEase: "非线性流光"
        case .linear: "恒速渐变"
        case .organicBreath: "柔和慢起"
        case .waveTide: "波浪推进"
        case .inkBloom: "有机扩散"
        case .velvetCurtain: "柔纱降临"
        }
    }

    public var symbolName: String {
        switch self {
        case .fluidEase: "waveform.path"
        case .linear: "line.diagonal"
        case .organicBreath: "wind"
        case .waveTide: "water.waves"
        case .inkBloom: "drop.halffull"
        case .velvetCurtain: "curtains.closed"
        }
    }

    public var menuTitle: String {
        "\(title) · \(shortTag)"
    }

    public var isSpatialMask: Bool {
        switch self {
        case .fluidEase, .linear, .organicBreath:
            return false
        case .waveTide, .inkBloom, .velvetCurtain:
            return true
        }
    }

    public var timingCurve: FocusTimingCurve {
        switch self {
        case .fluidEase:
            return .cubicBezier(c1x: 0.22, c1y: 1.0, c2x: 0.36, c2y: 1.0)
        case .linear:
            return .linear
        case .organicBreath:
            return .cubicBezier(c1x: 0.42, c1y: 0.0, c2x: 0.20, c2y: 1.0)
        case .waveTide:
            return .cubicBezier(c1x: 0.25, c1y: 0.92, c2x: 0.36, c2y: 1.0)
        case .inkBloom:
            return .cubicBezier(c1x: 0.20, c1y: 0.96, c2x: 0.30, c2y: 1.0)
        case .velvetCurtain:
            return .cubicBezier(c1x: 0.28, c1y: 0.92, c2x: 0.34, c2y: 1.0)
        }
    }

    public func resolvedFadeInDuration(baseDuration: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0.0 : FocusBounds.clampedTransitionDuration(baseDuration)
    }

    public func resolvedFadeOutDuration(baseDuration: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0.0 }
        let clamped = FocusBounds.clampedTransitionDuration(baseDuration)
        return max(FocusBounds.minimumTransitionDuration, clamped * 0.84)
    }

    public static func migratedDuration(fromLegacySpeed speed: FocusTransitionSpeed) -> Double {
        switch speed {
        case .crispCurve: 0.24
        case .softBreath: 0.55
        case .slowLinear: 0.85
        }
    }

    public static func migratedStyle(fromLegacySpeed speed: FocusTransitionSpeed) -> FocusTransitionStyle {
        switch speed {
        case .slowLinear: .linear
        case .softBreath, .crispCurve: .fluidEase
        }
    }

    public var legacySpeedEquivalent: FocusTransitionSpeed {
        switch self {
        case .linear: .slowLinear
        default: .softBreath
        }
    }

    public static func fromStoredValue(_ rawValue: String?) -> FocusTransitionStyle {
        guard let rawValue else { return .fluidEase }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "fluidEase", "softBreath", "gentle", "crispCurve", "snappy", "instant":
            return .fluidEase
        case "linear", "slowLinear":
            return .linear
        case "organicBreath":
            return .organicBreath
        case "waveTide":
            return .waveTide
        case "inkBloom":
            return .inkBloom
        case "velvetCurtain":
            return .velvetCurtain
        default:
            return .fluidEase
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try? container.decode(String.self)
        self = Self.fromStoredValue(rawValue)
    }
}

public enum FocusNoise2D {
    @inline(__always)
    public static func smootherstep(_ value: Double) -> Double {
        let t = min(max(value, 0.0), 1.0)
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    }

    @inline(__always)
    private static func hash2D(_ ix: Int, _ iy: Int) -> Double {
        var n = UInt64(bitPattern: Int64(ix)) &* 0x9E3779B97F4A7C15
        n ^= UInt64(bitPattern: Int64(iy)) &* 0xBF58476D1CE4E5B9
        n = (n ^ (n >> 30)) &* 0xBF58476D1CE4E5B9
        n = (n ^ (n >> 27)) &* 0x94D049BB133111EB
        n ^= (n >> 31)
        return Double(n & 0x00FF_FFFF) / Double(0x0100_0000)
    }

    @inline(__always)
    public static func valueNoise(x: Double, y: Double) -> Double {
        let floorX = floor(x)
        let floorY = floor(y)
        let ix = Int(floorX)
        let iy = Int(floorY)
        let fx = smootherstep(x - floorX)
        let fy = smootherstep(y - floorY)

        let v00 = hash2D(ix, iy)
        let v10 = hash2D(ix &+ 1, iy)
        let v01 = hash2D(ix, iy &+ 1)
        let v11 = hash2D(ix &+ 1, iy &+ 1)

        let a = v00 + (v10 - v00) * fx
        let b = v01 + (v11 - v01) * fx
        return a + (b - a) * fy
    }

    @inline(__always)
    public static func fbm(x: Double, y: Double, octaves: Int = 4) -> Double {
        var sum = 0.0
        var amplitude = 0.5
        var frequency = 1.0
        var normalization = 0.0
        var px = x
        var py = y
        for _ in 0..<max(1, octaves) {
            sum += amplitude * valueNoise(x: px * frequency, y: py * frequency)
            normalization += amplitude
            // Slight golden-angle rotation between octaves removes axis-aligned streaks.
            let nextX = px * 0.80 - py * 0.60 + 13.7
            let nextY = px * 0.60 + py * 0.80 + 7.3
            px = nextX
            py = nextY
            frequency *= 2.02
            amplitude *= 0.5
        }
        return normalization > 0 ? (sum / normalization) : 0.5
    }

    @inline(__always)
    public static func domainWarpedSigned(x: Double, y: Double) -> Double {
        let qx = fbm(x: x, y: y, octaves: 2) - 0.5
        let qy = fbm(x: x + 5.2, y: y + 1.3, octaves: 2) - 0.5
        let rx = fbm(x: x + 1.55 * qx + 1.7, y: y + 1.55 * qy + 9.2, octaves: 2) - 0.5
        let ry = fbm(x: x + 1.55 * qx + 8.3, y: y + 1.55 * qy + 2.8, octaves: 2) - 0.5
        let value = fbm(x: x + 1.35 * rx, y: y + 1.35 * ry, octaves: 3)
        return min(max((value - 0.5) * 2.3, -1.0), 1.0)
    }

    /// Deterministic triangular-PDF dithering offset in [-0.5/255, +0.5/255] to eliminate 8-bit Mach bands.
    @inline(__always)
    public static func triangularDither(pixelX: Int, pixelY: Int) -> Double {
        let r1 = hash2D(pixelX &* 3 &+ 11, pixelY &* 5 &+ 17)
        let r2 = hash2D(pixelX &* 7 &+ 29, pixelY &* 11 &+ 43)
        return (r1 + r2 - 1.0) * (0.5 / 255.0)
    }
}

public enum FocusSpatialTransitionMasks {
    public static let defaultSize = 512

    /// Evaluates the horizontally seamless 2-cycle multi-harmonic wave crest height in [0.38, 0.62].
    /// Even harmonics guarantee exact horizontal periodicity over half the texture width (1 full viewport roll).
    public static func waveCrestV(u: Double) -> Double {
        let theta = u * 2.0 * Double.pi
        let wave = sin(2.0 * theta) * 0.055
            + sin(4.0 * theta + 1.15) * 0.028
            + sin(6.0 * theta - 0.85) * 0.013
        return 0.50 + wave
    }

    /// Pre-bakes a 512x512 seamless wave mask:
    /// top band [0, ~0.35] strictly transparent, middle ~20% quintic soft crest, bottom band [~0.65, 1] strictly opaque.
    public static func makeWaveTideMaskImage(size: Int = defaultSize) -> CGImage? {
        let dim = max(64, size)
        var pixels = [UInt8](repeating: 0, count: dim * dim * 4)
        let denomY = Double(max(1, dim - 1))
        let halfFeather = 0.105

        for y in 0..<dim {
            let v = Double(y) / denomY
            for x in 0..<dim {
                let u = Double(x) / Double(dim)
                let crest = waveCrestV(u: u)
                let progress = (v - (crest - halfFeather)) / (2.0 * halfFeather)
                let weight: Double
                if y == 0 || progress <= 0.0 {
                    weight = 0.0
                } else if y == dim - 1 || progress >= 1.0 {
                    weight = 1.0
                } else {
                    let smooth = FocusNoise2D.smootherstep(progress)
                    weight = min(max(smooth + FocusNoise2D.triangularDither(pixelX: x, pixelY: y), 0.0), 1.0)
                }
                let alphaByte = UInt8((weight * 255.0).rounded())
                let offset = (y * dim + x) * 4
                pixels[offset] = alphaByte
                pixels[offset + 1] = alphaByte
                pixels[offset + 2] = alphaByte
                pixels[offset + 3] = alphaByte
            }
        }
        return makeRGBACGImage(pixels: pixels, width: dim, height: dim)
    }

    /// Evaluates organic wet-ink bloom weight in [0, 1] at (u, v) in [0, 1] x [0, 1].
    /// Center is strictly opaque (1.0); perimeter uses domain-warped fBm tendrils fading strictly to 0.0 before border.
    public static func inkBloomWeight(u: Double, v: Double) -> Double {
        let dx = u - 0.5
        let dy = v - 0.5
        let dist = hypot(dx, dy)
        if dist >= 0.495 { return 0.0 }
        let warp = FocusNoise2D.domainWarpedSigned(x: u * 4.4 + 2.3, y: v * 4.4 + 6.1)
        let outerRadius = 0.415 + warp * 0.072
        let innerRadius = max(0.16, outerRadius - 0.165)
        if dist <= innerRadius { return 1.0 }
        if dist >= outerRadius { return 0.0 }
        let t = 1.0 - (dist - innerRadius) / max(0.01, outerRadius - innerRadius)
        return FocusNoise2D.smootherstep(t)
    }

    /// Pre-bakes a 512x512 organic domain-warped ink blot mask with strictly transparent border.
    public static func makeInkBloomMaskImage(size: Int = defaultSize) -> CGImage? {
        let dim = max(64, size)
        var pixels = [UInt8](repeating: 0, count: dim * dim * 4)
        let denom = Double(max(1, dim - 1))

        for y in 0..<dim {
            let v = Double(y) / denom
            for x in 0..<dim {
                let u = Double(x) / denom
                let alphaByte: UInt8
                if x == 0 || y == 0 || x == dim - 1 || y == dim - 1 {
                    alphaByte = 0
                } else {
                    let raw = inkBloomWeight(u: u, v: v)
                    let dithered = (raw > 0.0 && raw < 1.0)
                        ? min(max(raw + FocusNoise2D.triangularDither(pixelX: x, pixelY: y), 0.0), 1.0)
                        : raw
                    alphaByte = UInt8((dithered * 255.0).rounded())
                }
                let offset = (y * dim + x) * 4
                pixels[offset] = alphaByte
                pixels[offset + 1] = alphaByte
                pixels[offset + 2] = alphaByte
                pixels[offset + 3] = alphaByte
            }
        }
        return makeRGBACGImage(pixels: pixels, width: dim, height: dim)
    }

    private static func makeRGBACGImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
