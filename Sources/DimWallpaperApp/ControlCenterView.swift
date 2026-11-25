import AppKit
import ServiceManagement
import SwiftUI
#if canImport(DimWallpaperCore)
import DimWallpaperCore
#endif

struct ControlCenterView: View {
    @ObservedObject var controller: DimWallpaperController
    let version: String
    let onQuit: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            headerSection
            DesktopPreviewCard(
                isDarkSystem: controller.state.isDarkAppearance,
                tint: controller.state.snapshot.tint,
                effectiveAlpha: controller.state.effectivePreviewAlpha,
                isEnabled: controller.state.snapshot.enabled,
                reduceTransparency: reduceTransparency
            )
            dimmingControlCard
            appearanceAndDisplaysCard
            hotKeyCard
            footerBar
        }
        .padding(14)
        .frame(width: 324)
        .background(panelBackground)
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Color.clear
        }
    }

    private var cardBackgroundColor: Color {
        if reduceTransparency {
            return Color(nsColor: .controlBackgroundColor)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.065)
            : Color.black.opacity(0.038)
    }

    private var cardBorderColor: Color {
        if reduceTransparency {
            return Color(nsColor: .separatorColor)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.08)
    }

    private var statusIndicatorColor: Color {
        if !controller.state.snapshot.enabled {
            return .secondary
        }
        if controller.state.isDimmingAnyDisplay {
            return Color.accentColor
        }
        return .orange
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            appEmblem
            VStack(alignment: .leading, spacing: 2) {
                Text("DimWallpaper")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 6.5, height: 6.5)
                    Text(controller.state.statusBadgeTitle)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(
                "启用壁纸调暗",
                isOn: Binding(
                    get: { controller.state.snapshot.enabled },
                    set: { controller.setEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var appEmblem: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.21, blue: 0.27),
                            Color(red: 0.08, green: 0.09, blue: 0.12),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Circle()
                .fill(Color(red: 0.95, green: 0.93, blue: 0.87))
                .frame(width: 16, height: 16)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.black.opacity(0.52))
                        .frame(height: 8.5)
                }
                .clipShape(Circle())
        }
        .frame(width: 28, height: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var dimmingControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("压暗强度")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(controller.state.intensityPercent)%")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(controller.state.snapshot.enabled ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(
                                controller.state.snapshot.enabled
                                    ? Color.accentColor.opacity(reduceTransparency ? 0.20 : 0.14)
                                    : Color.secondary.opacity(0.12)
                            )
                    )
            }

            Slider(
                value: Binding(
                    get: { controller.state.snapshot.intensity },
                    set: { controller.setIntensity($0) }
                ),
                in: DimmingBounds.minimumIntensity...DimmingBounds.maximumIntensity
            )
            .controlSize(.small)
            .disabled(!controller.state.snapshot.enabled)

            HStack(spacing: 6) {
                ForEach(DimmingPreset.allCases) { preset in
                    presetButton(for: preset)
                }
            }

            Divider()
                .opacity(reduceTransparency ? 0.9 : 0.45)

            HStack(spacing: 6) {
                Text("色温滤镜")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ForEach(DimmingTint.allCases) { tint in
                    tintPill(for: tint)
                }
            }
        }
        .padding(11)
        .background(cardSurface)
    }

    private func presetButton(for preset: DimmingPreset) -> some View {
        let isSelected = controller.state.activePreset == preset
        return Button {
            controller.applyPreset(preset)
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(preset.title)
                        .font(.system(size: 11, weight: .medium))
                }
                Text("\(preset.percentage)%")
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(reduceTransparency ? 0.22 : 0.16)
                            : (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.65) : cardBorderColor,
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(controller.state.snapshot.enabled ? 1 : 0.55)
    }

    private func tintPill(for tint: DimmingTint) -> some View {
        let isSelected = controller.state.snapshot.tint == tint
        let swatch = tint.swatchComponents
        return Button {
            controller.setTint(tint)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                Text(tint.title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(reduceTransparency ? 0.22 : 0.16)
                            : Color.clear
                    )
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.65) : cardBorderColor, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var appearanceAndDisplaysCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("仅在深色模式下生效")
                        .font(.system(size: 12, weight: .medium))
                    Text(controller.state.isDarkAppearance ? "当前系统外观：深色模式" : "当前系统外观：浅色模式")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "仅在深色模式下生效",
                    isOn: Binding(
                        get: { controller.state.snapshot.darkOnly },
                        set: { controller.setDarkOnly($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            Divider()
                .opacity(reduceTransparency ? 0.9 : 0.45)

            HStack {
                Text("显示器")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(controller.state.displays.count) 台在线")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }

            if controller.state.displays.isEmpty {
                Text("未检测到活动显示器")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(controller.state.displays) { display in
                        displayRow(display)
                    }
                }
            }
        }
        .padding(11)
        .background(cardSurface)
    }

    private func displayRow(_ display: DisplayDescriptor) -> some View {
        let excluded = controller.state.isDisplayExcluded(display.id)
        let decision = controller.state.decision(for: display.id)
        let dotColor: Color = excluded ? .orange : (decision.shouldShowWindow ? .green : .secondary)
        return HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 6.5, height: 6.5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(display.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    if display.isMain {
                        Text("主屏")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.14))
                            )
                    }
                }
                Text(display.resolutionLabel)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                display.name,
                isOn: Binding(
                    get: { !excluded },
                    set: { controller.setDisplayIncluded(display.id, included: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    private var hotKeyCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("全局切换快捷键")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(controller.state.snapshot.hotKeyBinding.displayLabel)
                    .font(.system(size: 10.5, weight: .semibold).monospaced())
                    .foregroundStyle(controller.state.snapshot.hotKeyEnabled ? .primary : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(cardBorderColor, lineWidth: 0.5)
                    )
                Toggle(
                    "启用全局快捷键",
                    isOn: Binding(
                        get: { controller.state.snapshot.hotKeyEnabled },
                        set: { controller.setHotKeyEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            if let hotKeyError = controller.hotKeyError {
                Text(hotKeyError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(cardSurface)
    }

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let loginError = controller.loginError {
                Text(loginError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    controller.toggleLoginItem()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(loginDotColor)
                            .frame(width: 6, height: 6)
                        Text(controller.loginController.statusLabel)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                    )
                    .overlay(Capsule().stroke(cardBorderColor, lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("v\(version)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)

                Button("退出") {
                    onQuit()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                )
                .overlay(Capsule().stroke(cardBorderColor, lineWidth: 0.5))
                .help("退出 DimWallpaper (⌘Q)")
            }
        }
    }

    private var loginDotColor: Color {
        switch controller.loginStatus {
        case .enabled: .green
        case .requiresApproval: .orange
        case .notRegistered, .notFound: .secondary
        @unknown default: .secondary
        }
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(cardBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: reduceTransparency ? 1 : 0.5)
            )
    }
}

private struct DesktopPreviewCard: View {
    let isDarkSystem: Bool
    let tint: DimmingTint
    let effectiveAlpha: Double
    let isEnabled: Bool
    let reduceTransparency: Bool

    private var readoutText: String {
        if effectiveAlpha > DimmingBounds.visibilityEpsilon {
            return "壁纸 -\(Int((effectiveAlpha * 100).rounded()))% · 窗口 100%"
        }
        return isEnabled ? "壁纸原色 · 100%" : "已暂停 · 壁纸原色"
    }

    var body: some View {
        let tintRGB = tint.components
        ZStack {
            Canvas { graphics, size in
                drawWallpaper(in: &graphics, size: size)
            }

            Color(red: tintRGB.red, green: tintRGB.green, blue: tintRGB.blue)
                .opacity(effectiveAlpha > DimmingBounds.visibilityEpsilon ? effectiveAlpha : 0)
                .animation(.easeInOut(duration: 0.22), value: effectiveAlpha)
                .animation(.easeInOut(duration: 0.22), value: tint)

            Canvas { graphics, size in
                drawUnaffectedDesktopElements(in: &graphics, size: size)
            }

            VStack {
                Spacer()
                HStack {
                    Text(readoutText)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(reduceTransparency ? 0.82 : 0.58))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
                        )
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 22)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    reduceTransparency ? Color(nsColor: .separatorColor) : Color.white.opacity(0.18),
                    lineWidth: reduceTransparency ? 1 : 0.75
                )
        )
    }

    private func drawWallpaper(in graphics: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let skyColors: [Color] = isDarkSystem
            ? [
                Color(red: 0.14, green: 0.24, blue: 0.48),
                Color(red: 0.34, green: 0.44, blue: 0.74),
                Color(red: 0.76, green: 0.62, blue: 0.78),
            ]
            : [
                Color(red: 0.26, green: 0.58, blue: 0.94),
                Color(red: 0.56, green: 0.78, blue: 0.98),
                Color(red: 0.96, green: 0.84, blue: 0.72),
            ]
        graphics.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: skyColors),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
            )
        )

        let glowRect = CGRect(
            x: size.width * 0.48,
            y: size.height * 0.08,
            width: size.width * 0.46,
            height: size.height * 0.56
        )
        graphics.fill(
            Path(ellipseIn: glowRect),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 1.0, green: 0.92, blue: 0.76).opacity(0.55),
                    Color.clear,
                ]),
                center: CGPoint(x: glowRect.midX, y: glowRect.midY),
                startRadius: 2,
                endRadius: glowRect.width * 0.55
            )
        )

        var farRidge = Path()
        farRidge.move(to: CGPoint(x: 0, y: size.height * 0.68))
        farRidge.addCurve(
            to: CGPoint(x: size.width * 0.55, y: size.height * 0.50),
            control1: CGPoint(x: size.width * 0.22, y: size.height * 0.52),
            control2: CGPoint(x: size.width * 0.38, y: size.height * 0.42)
        )
        farRidge.addCurve(
            to: CGPoint(x: size.width, y: size.height * 0.62),
            control1: CGPoint(x: size.width * 0.72, y: size.height * 0.58),
            control2: CGPoint(x: size.width * 0.86, y: size.height * 0.50)
        )
        farRidge.addLine(to: CGPoint(x: size.width, y: size.height))
        farRidge.addLine(to: CGPoint(x: 0, y: size.height))
        farRidge.closeSubpath()
        graphics.fill(
            farRidge,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.28, green: 0.36, blue: 0.62),
                    Color(red: 0.16, green: 0.22, blue: 0.40),
                ]),
                startPoint: CGPoint(x: 0, y: size.height * 0.45),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        var nearRidge = Path()
        nearRidge.move(to: CGPoint(x: 0, y: size.height * 0.78))
        nearRidge.addCurve(
            to: CGPoint(x: size.width * 0.62, y: size.height * 0.66),
            control1: CGPoint(x: size.width * 0.24, y: size.height * 0.64),
            control2: CGPoint(x: size.width * 0.44, y: size.height * 0.76)
        )
        nearRidge.addCurve(
            to: CGPoint(x: size.width, y: size.height * 0.74),
            control1: CGPoint(x: size.width * 0.80, y: size.height * 0.56),
            control2: CGPoint(x: size.width * 0.90, y: size.height * 0.68)
        )
        nearRidge.addLine(to: CGPoint(x: size.width, y: size.height))
        nearRidge.addLine(to: CGPoint(x: 0, y: size.height))
        nearRidge.closeSubpath()
        graphics.fill(
            nearRidge,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.15, green: 0.20, blue: 0.36),
                    Color(red: 0.08, green: 0.11, blue: 0.22),
                ]),
                startPoint: CGPoint(x: 0, y: size.height * 0.60),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
    }

    private func drawUnaffectedDesktopElements(in graphics: inout GraphicsContext, size: CGSize) {
        let menuBarRect = CGRect(x: 0, y: 0, width: size.width, height: 14)
        graphics.fill(
            Path(menuBarRect),
            with: .color(isDarkSystem ? Color.black.opacity(0.42) : Color.white.opacity(0.68))
        )
        for index in 0..<3 {
            let barDot = CGRect(x: size.width - 14 - CGFloat(index) * 9, y: 4.5, width: 5, height: 5)
            graphics.fill(
                Path(ellipseIn: barDot),
                with: .color(isDarkSystem ? Color.white.opacity(0.85) : Color.black.opacity(0.65))
            )
        }

        let iconX = size.width - 26
        for row in 0..<2 {
            let iconRect = CGRect(x: iconX, y: 24 + CGFloat(row) * 28, width: 16, height: 18)
            graphics.fill(
                Path(roundedRect: iconRect, cornerRadius: 3),
                with: .color(Color.white.opacity(0.92))
            )
            let labelRect = CGRect(x: iconX - 2, y: iconRect.maxY + 3, width: 20, height: 3)
            graphics.fill(
                Path(roundedRect: labelRect, cornerRadius: 1.5),
                with: .color(Color.white.opacity(0.75))
            )
        }

        let windowRect = CGRect(x: 16, y: 26, width: size.width * 0.56, height: size.height * 0.50)
        let windowPath = Path(roundedRect: windowRect, cornerRadius: 7)
        graphics.fill(
            windowPath,
            with: .color(isDarkSystem ? Color(red: 0.16, green: 0.17, blue: 0.20) : Color.white)
        )
        graphics.stroke(
            windowPath,
            with: .color(isDarkSystem ? Color.white.opacity(0.18) : Color.black.opacity(0.14)),
            lineWidth: 0.8
        )

        let trafficColors: [Color] = [
            Color(red: 1.0, green: 0.37, blue: 0.34),
            Color(red: 1.0, green: 0.74, blue: 0.18),
            Color(red: 0.15, green: 0.79, blue: 0.25),
        ]
        for (index, dotColor) in trafficColors.enumerated() {
            let dotRect = CGRect(x: windowRect.minX + 8 + CGFloat(index) * 9, y: windowRect.minY + 7, width: 5.5, height: 5.5)
            graphics.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
        }

        let lineColor = isDarkSystem ? Color.white.opacity(0.24) : Color.black.opacity(0.14)
        let lineWidths: [CGFloat] = [0.68, 0.82, 0.54]
        for (index, fraction) in lineWidths.enumerated() {
            let lineRect = CGRect(
                x: windowRect.minX + 10,
                y: windowRect.minY + 22 + CGFloat(index) * 11,
                width: (windowRect.width - 20) * fraction,
                height: 5
            )
            graphics.fill(Path(roundedRect: lineRect, cornerRadius: 2.5), with: .color(lineColor))
        }

        let dockWidth: CGFloat = 104
        let dockRect = CGRect(x: (size.width - dockWidth) / 2, y: size.height - 16, width: dockWidth, height: 12)
        let dockPath = Path(roundedRect: dockRect, cornerRadius: 6)
        graphics.fill(
            dockPath,
            with: .color(isDarkSystem ? Color.white.opacity(0.22) : Color.white.opacity(0.76))
        )
        let dockDotColors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal]
        for (index, appColor) in dockDotColors.enumerated() {
            let pipRect = CGRect(x: dockRect.minX + 10 + CGFloat(index) * 15, y: dockRect.minY + 2.5, width: 7, height: 7)
            graphics.fill(Path(roundedRect: pipRect, cornerRadius: 2), with: .color(appColor))
        }
    }
}
