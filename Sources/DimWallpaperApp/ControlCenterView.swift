import AppKit
import ServiceManagement
import SwiftUI
#if canImport(DimWallpaperCore)
import DimWallpaperCore
#endif

private enum ControlCenterTab: String, CaseIterable, Identifiable {
    case wallpaper
    case focus
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallpaper: "壁纸调暗"
        case .focus: "专注遮罩"
        case .general: "通用与热键"
        }
    }

    var symbolName: String {
        switch self {
        case .wallpaper: "photo.fill"
        case .focus: "viewfinder"
        case .general: "command"
        }
    }
}

@MainActor
private final class FlippedDocumentContainerView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private struct BorderlessVerticalScrollView<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let resetToken: AnyHashable
    let onContentHeightChange: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    @MainActor
    final class Coordinator {
        let documentContainer = FlippedDocumentContainerView(frame: .zero)
        var hostingView: NSHostingView<Content>?
        var lastResetToken: AnyHashable?
        var lastReportedHeight: CGFloat = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: contentWidth, height: 320))
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false

        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = true
        context.coordinator.hostingView = hosting
        context.coordinator.documentContainer.addSubview(hosting)
        scrollView.documentView = context.coordinator.documentContainer

        syncLayout(in: scrollView, coordinator: context.coordinator, resetToTop: true)
        context.coordinator.lastResetToken = resetToken
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay

        let shouldReset = context.coordinator.lastResetToken != resetToken
        context.coordinator.lastResetToken = resetToken
        context.coordinator.hostingView?.rootView = content()
        syncLayout(in: scrollView, coordinator: context.coordinator, resetToTop: shouldReset)
    }

    private func syncLayout(in scrollView: NSScrollView, coordinator: Coordinator, resetToTop: Bool) {
        guard let hosting = coordinator.hostingView else { return }
        let targetWidth = max(1, contentWidth)
        hosting.frame = CGRect(x: 0, y: 0, width: targetWidth, height: max(1, hosting.frame.height))
        hosting.layoutSubtreeIfNeeded()
        let measuredHeight = max(1, ceil(hosting.fittingSize.height))
        hosting.frame = CGRect(x: 0, y: 0, width: targetWidth, height: measuredHeight)

        let visibleHeight = scrollView.contentSize.height
        let documentHeight = max(visibleHeight, measuredHeight)
        coordinator.documentContainer.frame = CGRect(x: 0, y: 0, width: targetWidth, height: documentHeight)

        if resetToTop {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            let maxOffsetY = max(0, documentHeight - visibleHeight)
            let currentY = scrollView.contentView.bounds.origin.y
            if currentY > maxOffsetY {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxOffsetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        if measuredHeight.isFinite, abs(coordinator.lastReportedHeight - measuredHeight) > 0.5 {
            coordinator.lastReportedHeight = measuredHeight
            let report = onContentHeightChange
            Task { @MainActor in
                report(measuredHeight)
            }
        }
    }
}

struct ControlCenterView: View {
    @ObservedObject var controller: DimWallpaperController
    let version: String
    let onQuit: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: ControlCenterTab = .wallpaper
    @State private var measuredContentHeight: CGFloat = 390
    @State private var screenVisibleHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 860
    @State private var durationBeforeDrag: Double?

    private var maxScrollHeight: CGFloat {
        min(460, max(300, screenVisibleHeight - 220))
    }

    private var resolvedScrollHeight: CGFloat {
        min(max(measuredContentHeight, 240), maxScrollHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                headerSection
                quickModeCapsules
                tabSelector
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 9)

            Divider()
                .opacity(reduceTransparency ? 0.9 : 0.45)

            BorderlessVerticalScrollView(
                contentWidth: 372,
                resetToken: selectedTab,
                onContentHeightChange: { nextHeight in
                    guard nextHeight.isFinite, nextHeight > 1 else { return }
                    if abs(measuredContentHeight - nextHeight) > 0.5 {
                        measuredContentHeight = nextHeight
                    }
                }
            ) {
                VStack(spacing: 9) {
                    DesktopPreviewCard(
                        isDarkSystem: controller.state.isDarkAppearance,
                        wallpaperTint: controller.state.snapshot.tint,
                        wallpaperAlpha: controller.state.effectivePreviewAlpha,
                        wallpaperEnabled: controller.state.snapshot.enabled,
                        focusTint: controller.state.resolvedFocusTint,
                        focusAlpha: controller.isFocusPausedByExcludedApp ? 0 : controller.state.effectiveFocusPreviewAlpha,
                        focusEnabled: controller.state.snapshot.focusEnabled,
                        focusPausedByExclusion: controller.isFocusPausedByExcludedApp,
                        dimMenuBar: controller.state.snapshot.dimMenuBar,
                        dimDock: controller.state.snapshot.dimDock,
                        focusScope: controller.state.snapshot.focusScope,
                        reduceTransparency: reduceTransparency
                    )

                    switch selectedTab {
                    case .wallpaper:
                        dimmingControlCard
                        appearanceAndDisplaysCard
                    case .focus:
                        focusControlCard
                        focusSystemBarsCard
                        focusBehaviorCard
                        focusTargetCard
                    case .general:
                        hotKeyCard
                        generalInfoCard
                        aboutAppCard
                    }
                }
                .id(selectedTab)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 372, alignment: .top)
            }
            .frame(height: resolvedScrollHeight)

            Divider()
                .opacity(reduceTransparency ? 0.9 : 0.45)

            footerBar
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .frame(width: 372)
        .background(panelBackground.ignoresSafeArea())
        .onAppear {
            if let currentHeight = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.height,
               currentHeight.isFinite,
               currentHeight > 200 {
                screenVisibleHeight = currentHeight
            }
            if controller.state.snapshot.focusEnabled && !controller.state.snapshot.enabled {
                selectedTab = .focus
            }
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else if colorScheme == .dark {
            Color.black.opacity(0.18)
        } else {
            Color.white.opacity(0.74)
        }
    }

    private var cardBackgroundColor: Color {
        if reduceTransparency {
            return Color(nsColor: .controlBackgroundColor)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.065)
            : Color.white.opacity(0.55)
    }

    private var cardBorderColor: Color {
        if reduceTransparency {
            return Color(nsColor: .separatorColor)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.07)
    }

    private var focusAccentColor: Color {
        colorScheme == .dark
            ? Color(red: 0.58, green: 0.60, blue: 1.0)
            : Color(red: 0.27, green: 0.24, blue: 0.78)
    }

    private var statusIndicatorColor: Color {
        if controller.state.isDimmingAnyDisplay && controller.state.isFocusGloballyActive {
            return .purple
        }
        if controller.state.isFocusGloballyActive {
            return controller.isFocusPausedByExcludedApp ? .orange : Color.accentColor
        }
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
                    Text(controller.isFocusPausedByExcludedApp && controller.state.isFocusGloballyActive ? "专注已豁免" : controller.state.statusBadgeTitle)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var quickModeCapsules: some View {
        HStack(spacing: 7) {
            quickModeButton(
                title: "壁纸调暗",
                detail: controller.state.snapshot.enabled ? "\(controller.state.intensityPercent)%" : "已关闭",
                symbol: "moon.fill",
                isActive: controller.state.snapshot.enabled,
                tint: Color.accentColor
            ) {
                controller.toggleEnabled()
            }

            quickModeButton(
                title: "专注遮罩",
                detail: controller.state.snapshot.focusEnabled ? "\(controller.state.focusIntensityPercent)%" : "已关闭",
                symbol: "viewfinder",
                isActive: controller.state.snapshot.focusEnabled,
                tint: Color.indigo
            ) {
                controller.toggleFocusEnabled()
            }
        }
    }

    private func quickModeButton(
        title: String,
        detail: String,
        symbol: String,
        isActive: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isActive ? tint : .secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(
                            isActive
                                ? tint.opacity(reduceTransparency ? 0.24 : 0.18)
                                : Color.secondary.opacity(0.12)
                        )
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(isActive ? tint : .secondary)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(isActive ? tint : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isActive
                            ? tint.opacity(reduceTransparency ? 0.18 : 0.11)
                            : cardBackgroundColor
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isActive ? tint.opacity(0.55) : cardBorderColor, lineWidth: isActive ? 1 : 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(ControlCenterTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5.5)
                    .background(
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .fill(
                                isSelected
                                    ? (reduceTransparency
                                       ? Color(nsColor: .selectedControlColor).opacity(0.24)
                                       : (colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.86)))
                                    : Color.clear
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .stroke(isSelected ? cardBorderColor : .clear, lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 0.5)
        )
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

    // MARK: - Focus Mode Cards

    private var focusControlCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("后台压暗强度")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(controller.state.focusIntensityPercent)%")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(controller.state.snapshot.focusEnabled ? Color.indigo : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(
                                controller.state.snapshot.focusEnabled
                                    ? Color.indigo.opacity(reduceTransparency ? 0.22 : 0.15)
                                    : Color.secondary.opacity(0.12)
                            )
                    )
            }

            Slider(
                value: Binding(
                    get: { controller.state.snapshot.focusIntensity },
                    set: { controller.setFocusIntensity($0) }
                ),
                in: FocusBounds.minimumIntensity...FocusBounds.maximumIntensity
            )
            .controlSize(.small)
            .disabled(!controller.state.snapshot.focusEnabled)

            HStack(spacing: 6) {
                ForEach(FocusPreset.allCases) { preset in
                    focusPresetButton(for: preset)
                }
            }

            Divider()
                .opacity(reduceTransparency ? 0.9 : 0.45)

            HStack(spacing: 4) {
                Text("专注色调")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                ForEach(FocusTintOption.allCases) { option in
                    focusTintPill(for: option)
                }
            }
        }
        .padding(11)
        .background(cardSurface)
    }

    private func focusPresetButton(for preset: FocusPreset) -> some View {
        let isSelected = controller.state.activeFocusPreset == preset && controller.state.snapshot.focusEnabled
        return Button {
            controller.applyFocusPreset(preset)
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
                    .foregroundStyle(isSelected ? Color.indigo : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.indigo.opacity(reduceTransparency ? 0.24 : 0.16)
                            : (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? Color.indigo.opacity(0.65) : cardBorderColor,
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(controller.state.snapshot.focusEnabled ? 1 : 0.62)
    }

    private func focusTintPill(for option: FocusTintOption) -> some View {
        let isSelected = controller.state.snapshot.focusTint == option
        return Button {
            controller.setFocusTint(option)
        } label: {
            Text(option.title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 6.5)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? Color.indigo.opacity(reduceTransparency ? 0.24 : 0.16)
                                : Color.clear
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.indigo.opacity(0.65) : cardBorderColor, lineWidth: isSelected ? 1 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var focusSystemBarsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("菜单栏与 Dock")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if controller.state.focusSystemBarPreset == nil {
                    Text("自定义")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(focusAccentColor)
                }
            }

            HStack(spacing: 6) {
                ForEach(FocusSystemBarPreset.allCases) { preset in
                    let isSelected = controller.state.focusSystemBarPreset == preset
                    Button {
                        controller.applyFocusSystemBarPreset(preset)
                    } label: {
                        Text(preset.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5.5)
                            .background(
                                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? focusAccentColor.opacity(reduceTransparency ? 0.22 : 0.16)
                                            : (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                    .stroke(isSelected ? focusAccentColor.opacity(0.65) : cardBorderColor, lineWidth: isSelected ? 1 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    "连同菜单栏文字图标一并压暗",
                    isOn: Binding(
                        get: { controller.state.snapshot.dimMenuBar },
                        set: { controller.setDimMenuBar($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

                Toggle(
                    "连同程序坞 Dock 图标一并压暗",
                    isOn: Binding(
                        get: { controller.state.snapshot.dimDock },
                        set: { controller.setDimDock($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            }

            Text(
                controller.state.snapshot.dimMenuBar
                    ? "当前已勾选连同菜单栏文字图标一并压暗；取消勾选即可保留菜单栏亮色图标（仅压暗背景）"
                    : "保留菜单栏亮色图标（仅压暗背景），与 Dock 一样和桌面无缝一体变暗、文字图标保持原亮"
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(cardSurface)
    }

    private var focusBehaviorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("聚焦粒度")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Picker(
                    "聚焦粒度",
                    selection: Binding(
                        get: { controller.state.snapshot.focusScope },
                        set: { controller.setFocusScope($0) }
                    )
                ) {
                    ForEach(FocusScope.allCases) { scope in
                        Text(scope.shortTitle).tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 174)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("多屏策略")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker(
                    "多屏策略",
                    selection: Binding(
                        get: { controller.state.snapshot.focusMultiDisplayPolicy },
                        set: { controller.setFocusMultiDisplayPolicy($0) }
                    )
                ) {
                    ForEach(FocusMultiDisplayPolicy.allCases) { policy in
                        Text(policy.shortTitle).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)

                Text(controller.state.snapshot.focusMultiDisplayPolicy.detailDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .opacity(reduceTransparency ? 0.9 : 0.45)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("全屏视频自动豁免")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("原生全屏或无边框全屏播放时自动隐藏该屏遮罩")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Toggle(
                    "全屏视频自动豁免",
                    isOn: Binding(
                        get: { controller.state.snapshot.pauseFocusOnFullscreen },
                        set: { controller.setPauseFocusOnFullscreen($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            Divider()
                .opacity(reduceTransparency ? 0.9 : 0.45)

            VStack(alignment: .leading, spacing: 7) {
                let activeTransitionStyle = controller.state.snapshot.focusTransitionStyle
                let activeDuration = controller.state.snapshot.focusTransitionDuration

                HStack(spacing: 6) {
                    Text("过渡动画")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2fs", activeDuration))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(focusAccentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(focusAccentColor.opacity(reduceTransparency ? 0.22 : 0.14))
                        )

                    Button {
                        controller.previewFocusTransition()
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("预览动效")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(focusAccentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(focusAccentColor.opacity(reduceTransparency ? 0.20 : 0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(focusAccentColor.opacity(0.55), lineWidth: 0.7)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("在真实桌面遮罩上演练一次完整的退场与进场过渡动画")
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("过渡时长")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("0.08s – 2.00s")
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Slider(
                        value: Binding(
                            get: { controller.state.snapshot.focusTransitionDuration },
                            set: { controller.setFocusTransitionDuration(($0 * 50.0).rounded() / 50.0) }
                        ),
                        in: FocusBounds.minimumTransitionDuration...FocusBounds.maximumTransitionDuration,
                        onEditingChanged: { editing in
                            if editing {
                                durationBeforeDrag = controller.state.snapshot.focusTransitionDuration
                            } else {
                                if let before = durationBeforeDrag,
                                   abs(before - controller.state.snapshot.focusTransitionDuration) > 0.005 {
                                    controller.previewFocusTransition()
                                }
                                durationBeforeDrag = nil
                            }
                        }
                    )
                    .controlSize(.small)
                    .tint(focusAccentColor)
                }

                let transitionColumns = [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6),
                ]
                LazyVGrid(columns: transitionColumns, spacing: 6) {
                    ForEach(FocusTransitionStyle.allCases) { style in
                        let isSelected = activeTransitionStyle == style
                        Button {
                            controller.setFocusTransitionStyle(style, previewIfActive: true)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: style.symbolName)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(isSelected ? focusAccentColor : Color.secondary)
                                Text(style.title)
                                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .lineLimit(1)
                                Text(style.shortTag)
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundStyle(isSelected ? focusAccentColor : Color.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6.5)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? focusAccentColor.opacity(reduceTransparency ? 0.22 : 0.15)
                                            : (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? focusAccentColor.opacity(0.72) : cardBorderColor, lineWidth: isSelected ? 1 : 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(11)
        .background(cardSurface)
    }

    private var focusTargetCard: some View {
        let trackedApp = controller.trackedExternalApp
        let trackedExcluded = controller.state.isAppExcludedFromFocus(bundleID: trackedApp?.bundleIdentifier)
        let excludedList = controller.state.snapshot.focusExcludedBundleIDs.sorted()

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: trackedExcluded ? "pause.circle.fill" : "macwindow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(trackedExcluded ? .orange : .indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(trackedApp.map { "当前外部焦点：\($0.localizedName)" } ?? "等待外部应用窗口")
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text(trackedExcluded ? "此应用已在专注豁免名单中，已自动暂停压暗" : "拖动上方滑杆时保持外部前台应用高亮预览")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let bundleID = trackedApp?.bundleIdentifier, !bundleID.isEmpty {
                    Button(trackedExcluded ? "恢复压暗" : "豁免此应用") {
                        controller.toggleTrackedAppFocusExclusion()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if !excludedList.isEmpty {
                Divider()
                    .opacity(reduceTransparency ? 0.9 : 0.45)
                HStack {
                    Text("已豁免应用（\(excludedList.count)）")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                VStack(spacing: 4) {
                    ForEach(excludedList.prefix(4), id: \.self) { bundleID in
                        HStack(spacing: 6) {
                            Text(bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                controller.setFocusExcludedApp(bundleID, excluded: false)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("移出豁免名单")
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(cardSurface)
    }

    private var hotKeyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            hotKeyRow(
                title: "切换壁纸调暗",
                symbol: "moon.fill",
                bindingLabel: controller.state.snapshot.hotKeyBinding.displayLabel,
                isEnabled: Binding(
                    get: { controller.state.snapshot.hotKeyEnabled },
                    set: { controller.setHotKeyEnabled($0) }
                )
            )
            if let hotKeyError = controller.hotKeyError {
                Text(hotKeyError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .opacity(reduceTransparency ? 0.9 : 0.45)

            hotKeyRow(
                title: "切换专注遮罩",
                symbol: "viewfinder",
                bindingLabel: controller.state.snapshot.focusHotKeyBinding.displayLabel,
                isEnabled: Binding(
                    get: { controller.state.snapshot.focusHotKeyEnabled },
                    set: { controller.setFocusHotKeyEnabled($0) }
                )
            )
            if let focusHotKeyError = controller.focusHotKeyError {
                Text(focusHotKeyError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(cardSurface)
    }

    private func hotKeyRow(
        title: String,
        symbol: String,
        bindingLabel: String,
        isEnabled: Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(bindingLabel)
                .font(.system(size: 11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(cardBorderColor, lineWidth: 0.5)
                )
            Toggle(title, isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private var generalInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("显示与安全边界")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(controller.state.displays.count) 台在线显示器")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("双层遮罩全部通过无边框鼠标穿透 NSWindow 合成，不修改硬件 Gamma/色表/亮度，无需录屏或辅助功能权限。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(cardSurface)
    }

    private var aboutAppCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text("DimWallpaper")
                            .font(.system(size: 12, weight: .semibold))
                        Text("v\(version)")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("由 Xin (@xxkingstuggle) 设计与开发")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                aboutLinkPill(title: "官网 myzjx.com", symbol: "globe", urlString: "https://myzjx.com")
                aboutLinkPill(title: "产品主页", symbol: "sparkles", urlString: "https://myzjx.com/software/dim-wallpaper/")
                aboutLinkPill(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", urlString: "https://github.com/xxkingstuggle")
            }

            Text("© 2026 Xin (@xxkingstuggle) · MIT License")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(cardSurface)
    }

    private func aboutLinkPill(title: String, symbol: String, urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055))
            )
            .overlay(Capsule().stroke(cardBorderColor, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(urlString)
    }

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let loginError = controller.loginError {
                Text(loginError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Button {
                    controller.toggleLoginItem()
                } label: {
                    HStack(spacing: 4.5) {
                        Circle()
                            .fill(loginDotColor)
                            .frame(width: 5.5, height: 5.5)
                        Text(controller.loginController.compactStatusLabel)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7.5)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                    )
                    .overlay(Capsule().stroke(cardBorderColor, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help(controller.loginController.statusLabel)

                Spacer(minLength: 4)

                Button {
                    if let url = URL(string: "https://myzjx.com/software/dim-wallpaper/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("@xxkingstuggle · myzjx.com")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .help("访问 DimWallpaper 官网主页 (myzjx.com)")

                Spacer(minLength: 4)

                Text("v\(version)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button("退出") {
                    onQuit()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
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
    let wallpaperTint: DimmingTint
    let wallpaperAlpha: Double
    let wallpaperEnabled: Bool
    let focusTint: DimmingTint
    let focusAlpha: Double
    let focusEnabled: Bool
    let focusPausedByExclusion: Bool
    let dimMenuBar: Bool
    let dimDock: Bool
    let focusScope: FocusScope
    let reduceTransparency: Bool

    private var isWallpaperDimming: Bool {
        wallpaperAlpha > DimmingBounds.visibilityEpsilon
    }

    private var isFocusDimming: Bool {
        focusAlpha > FocusBounds.visibilityEpsilon
    }

    private var readoutText: String {
        let wallPct = Int((wallpaperAlpha * 100).rounded())
        let focusPct = Int((focusAlpha * 100).rounded())
        if isWallpaperDimming && isFocusDimming {
            return "双重沉浸 · 壁纸 \(wallPct)% / 专注 \(focusPct)%"
        }
        if isFocusDimming {
            let barHint = (dimMenuBar && dimDock) ? "含栏" : ((dimMenuBar || dimDock) ? "部分栏" : "留栏")
            return "专注遮罩 · \(focusPct)%（\(focusScope.shortTitle) · \(barHint)）"
        }
        if focusEnabled && focusPausedByExclusion {
            return "专注已豁免当前应用"
        }
        if isWallpaperDimming {
            return "壁纸 -\(wallPct)% · 窗口 100%"
        }
        return wallpaperEnabled ? "壁纸原色 · 100%" : "全部已暂停 · 原色"
    }

    var body: some View {
        let wallRGB = wallpaperTint.components
        let focusRGB = focusTint.components
        ZStack {
            Canvas { graphics, size in
                drawWallpaper(in: &graphics, size: size)
            }

            Color(red: wallRGB.red, green: wallRGB.green, blue: wallRGB.blue)
                .opacity(isWallpaperDimming ? wallpaperAlpha : 0)
                .animation(.easeInOut(duration: 0.20), value: wallpaperAlpha)
                .animation(.easeInOut(duration: 0.20), value: wallpaperTint)

            Canvas { graphics, size in
                drawBackgroundDesktopLayer(in: &graphics, size: size)
            }

            previewFocusOverlay(focusRGB: focusRGB)

            Canvas { graphics, size in
                drawForegroundAndSystemChrome(in: &graphics, size: size)
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
                .padding(.bottom, 18)
            }
        }
        .frame(height: 120)
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

    private func drawBackgroundDesktopLayer(in graphics: inout GraphicsContext, size: CGSize) {
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

        let backWindowRect = CGRect(x: 12, y: 22, width: size.width * 0.48, height: size.height * 0.44)
        drawMockAppWindow(in: &graphics, rect: backWindowRect, isActive: false)
    }

    @ViewBuilder
    private func previewFocusOverlay(focusRGB: TintComponents) -> some View {
        if isFocusDimming {
            Color(red: focusRGB.red, green: focusRGB.green, blue: focusRGB.blue)
                .opacity(focusAlpha)
                .animation(.easeInOut(duration: 0.20), value: focusAlpha)
                .animation(.easeInOut(duration: 0.20), value: focusTint)
        }
    }

    private func drawForegroundAndSystemChrome(in graphics: inout GraphicsContext, size: CGSize) {
        let focusRGB = focusTint.components
        let focusOverlayColor = Color(red: focusRGB.red, green: focusRGB.green, blue: focusRGB.blue)

        let frontWindowRect = CGRect(x: size.width * 0.24, y: 26, width: size.width * 0.54, height: size.height * 0.50)
        drawMockAppWindow(in: &graphics, rect: frontWindowRect, isActive: true)

        let menuBarRect = CGRect(x: 0, y: 0, width: size.width, height: 14)
        graphics.fill(
            Path(menuBarRect),
            with: .color(
                isFocusDimming
                    ? Color.white.opacity(isDarkSystem ? 0.04 : 0.08)
                    : (isDarkSystem ? Color.black.opacity(0.24) : Color.white.opacity(0.32))
            )
        )
        let menuInkColor: Color = (isFocusDimming || isDarkSystem)
            ? Color.white.opacity(0.92)
            : Color.black.opacity(0.68)
        let appleDot = CGRect(x: 9, y: 4.5, width: 5, height: 5)
        graphics.fill(Path(ellipseIn: appleDot), with: .color(menuInkColor))
        let menuStripA = CGRect(x: 18, y: 5.5, width: 16, height: 3)
        let menuStripB = CGRect(x: 38, y: 5.5, width: 12, height: 3)
        graphics.fill(Path(roundedRect: menuStripA, cornerRadius: 1.5), with: .color(menuInkColor.opacity(0.88)))
        graphics.fill(Path(roundedRect: menuStripB, cornerRadius: 1.5), with: .color(menuInkColor.opacity(0.65)))
        for index in 0..<3 {
            let barDot = CGRect(x: size.width - 14 - CGFloat(index) * 9, y: 4.5, width: 5, height: 5)
            graphics.fill(
                Path(ellipseIn: barDot),
                with: .color(menuInkColor)
            )
        }
        if isFocusDimming && dimMenuBar {
            graphics.fill(
                Path(menuBarRect),
                with: .color(focusOverlayColor.opacity(focusAlpha))
            )
        }

        let dockWidth: CGFloat = 104
        let dockRect = CGRect(x: (size.width - dockWidth) / 2, y: size.height - 16, width: dockWidth, height: 12)
        let dockPath = Path(roundedRect: dockRect, cornerRadius: 6)
        graphics.fill(
            dockPath,
            with: .color(
                isFocusDimming
                    ? Color.white.opacity(0.22)
                    : (isDarkSystem ? Color.white.opacity(0.22) : Color.white.opacity(0.76))
            )
        )
        let dockDotColors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal]
        for (index, appColor) in dockDotColors.enumerated() {
            let pipRect = CGRect(x: dockRect.minX + 10 + CGFloat(index) * 15, y: dockRect.minY + 2.5, width: 7, height: 7)
            graphics.fill(Path(roundedRect: pipRect, cornerRadius: 2), with: .color(appColor))
        }
        if isFocusDimming && dimDock {
            graphics.fill(
                dockPath,
                with: .color(focusOverlayColor.opacity(focusAlpha))
            )
        }
    }

    private func drawMockAppWindow(in graphics: inout GraphicsContext, rect: CGRect, isActive: Bool) {
        let windowPath = Path(roundedRect: rect, cornerRadius: 7)
        let bodyColor: Color = isDarkSystem
            ? (isActive ? Color(red: 0.19, green: 0.20, blue: 0.24) : Color(red: 0.14, green: 0.15, blue: 0.18))
            : (isActive ? Color.white : Color(red: 0.94, green: 0.95, blue: 0.97))
        graphics.fill(windowPath, with: .color(bodyColor))
        graphics.stroke(
            windowPath,
            with: .color(
                isActive && isFocusDimming
                    ? Color.white.opacity(isDarkSystem ? 0.42 : 0.85)
                    : (isDarkSystem ? Color.white.opacity(0.18) : Color.black.opacity(0.14))
            ),
            lineWidth: isActive && isFocusDimming ? 1.1 : 0.75
        )

        let trafficColors: [Color] = isActive
            ? [
                Color(red: 1.0, green: 0.37, blue: 0.34),
                Color(red: 1.0, green: 0.74, blue: 0.18),
                Color(red: 0.15, green: 0.79, blue: 0.25),
            ]
            : [Color.gray.opacity(0.55), Color.gray.opacity(0.45), Color.gray.opacity(0.45)]
        for (index, dotColor) in trafficColors.enumerated() {
            let dotRect = CGRect(x: rect.minX + 8 + CGFloat(index) * 8.5, y: rect.minY + 6.5, width: 5, height: 5)
            graphics.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
        }

        let lineColor = isDarkSystem
            ? Color.white.opacity(isActive ? 0.30 : 0.18)
            : Color.black.opacity(isActive ? 0.18 : 0.11)
        let lineWidths: [CGFloat] = [0.68, 0.82, 0.54]
        for (index, fraction) in lineWidths.enumerated() {
            let lineRect = CGRect(
                x: rect.minX + 10,
                y: rect.minY + 20 + CGFloat(index) * 10,
                width: (rect.width - 20) * fraction,
                height: 4.5
            )
            graphics.fill(Path(roundedRect: lineRect, cornerRadius: 2.2), with: .color(lineColor))
        }
    }
}
