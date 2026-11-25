import AppKit
import Combine
import CoreGraphics
import QuartzCore
import ServiceManagement
#if canImport(DimWallpaperCore)
import DimWallpaperCore
#endif

@MainActor
final class DimWallpaperController: ObservableObject {
    @Published private(set) var state: DimmingEngineState
    @Published private(set) var hotKeyError: String?
    @Published private(set) var loginStatus: SMAppService.Status
    @Published private(set) var loginError: String?

    var onStatusAppearanceChanged: (() -> Void)?

    let store: PreferencesStore
    let launchOptions: LaunchOptions
    let loginController = LoginItemController()

    private let hotKeyManager = GlobalHotKeyManager()
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var animationTokens: [CGDirectDisplayID: UInt64] = [:]
    private var appearanceObserver: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var pendingScreenSync: DispatchWorkItem?
    private var pendingAppearanceSync: DispatchWorkItem?
    private var pendingPersistenceSave: DispatchWorkItem?
    private var isStarted = false

    private let desktopLevel: NSWindow.Level = {
        let baseLevel = CGWindowLevelForKey(.desktopWindow)
        let iconLevel = CGWindowLevelForKey(.desktopIconWindow)
        let resolved = OverlayWindowPolicy.resolvedWindowLevel(desktopLevel: baseLevel, desktopIconLevel: iconLevel)
        assert(OverlayWindowPolicy.isStrictlyBetweenDesktopAndIcons(level: resolved, desktopLevel: baseLevel, desktopIconLevel: iconLevel))
        return NSWindow.Level(rawValue: resolved)
    }()

    init(launchOptions: LaunchOptions) {
        self.launchOptions = launchOptions
        let preferences = PreferencesStore(suiteName: launchOptions.defaultsSuiteName)
        self.store = preferences
        let initialSnapshot = preferences.load()
        let initialDisplays = Self.captureOnlineDisplays()
        self.state = DimmingEngineState(
            snapshot: initialSnapshot,
            isDarkAppearance: Self.currentSystemIsDark(),
            displays: initialDisplays
        )
        self.loginStatus = loginController.status
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        state.isDarkAppearance = Self.currentSystemIsDark()
        state.updateDisplays(Self.captureOnlineDisplays())

        hotKeyManager.onPressed = { [weak self] in
            self?.toggleEnabled()
        }
        syncHotKeyRegistration()

        loginController.setupOnFirstLaunchIfNeeded(store: store, disabled: launchOptions.disableLoginItemSetup)
        refreshLoginStatus()

        installObservers()
        rebuildWindows(forceDisplay: true)
        applyOverlays(animated: false)
        onStatusAppearanceChanged?()
    }

    func shutdown() {
        pendingScreenSync?.cancel()
        pendingScreenSync = nil
        pendingAppearanceSync?.cancel()
        pendingAppearanceSync = nil
        flushPersistence()

        appearanceObserver?.invalidate()
        appearanceObserver = nil

        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens {
            workspaceCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        for token in distributedTokens {
            distributedCenter.removeObserver(token)
        }
        distributedTokens.removeAll()

        hotKeyManager.shutdown()

        for (displayID, window) in windows {
            animationTokens[displayID] = (animationTokens[displayID] ?? 0) &+ 1
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        animationTokens.removeAll()
        isStarted = false
    }

    // MARK: - User Actions

    func setEnabled(_ value: Bool) {
        guard state.snapshot.enabled != value else { return }
        state.setEnabled(value)
        persistImmediately()
        applyOverlays(animated: true)
        onStatusAppearanceChanged?()
    }

    func toggleEnabled() {
        setEnabled(!state.snapshot.enabled)
    }

    func setIntensity(_ value: Double) {
        let clamped = DimmingBounds.clampedIntensity(value)
        guard abs(state.snapshot.intensity - clamped) > 0.0001 else { return }
        state.setIntensity(clamped)
        scheduleDebouncedPersistence()
        applyOverlays(animated: false)
        onStatusAppearanceChanged?()
    }

    func applyPreset(_ preset: DimmingPreset) {
        state.applyPreset(preset)
        persistImmediately()
        applyOverlays(animated: true)
        onStatusAppearanceChanged?()
    }

    func setDarkOnly(_ value: Bool) {
        guard state.snapshot.darkOnly != value else { return }
        state.setDarkOnly(value)
        persistImmediately()
        applyOverlays(animated: true)
        onStatusAppearanceChanged?()
    }

    func setTint(_ value: DimmingTint) {
        guard state.snapshot.tint != value else { return }
        state.setTint(value)
        persistImmediately()
        applyOverlays(animated: true)
        onStatusAppearanceChanged?()
    }

    func setDisplayIncluded(_ displayID: UInt32, included: Bool) {
        let shouldExclude = !included
        guard state.isDisplayExcluded(displayID) != shouldExclude else { return }
        state.setDisplayExcluded(displayID, excluded: shouldExclude)
        persistImmediately()
        applyOverlays(animated: true)
        onStatusAppearanceChanged?()
    }

    func setHotKeyEnabled(_ value: Bool) {
        guard state.snapshot.hotKeyEnabled != value else { return }
        state.setHotKeyEnabled(value)
        persistImmediately()
        syncHotKeyRegistration()
    }

    func toggleLoginItem() {
        loginError = loginController.toggle()
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        loginStatus = loginController.status
    }

    func refreshDisplaysNow() {
        state.updateDisplays(Self.captureOnlineDisplays())
        rebuildWindows(forceDisplay: true)
        applyOverlays(animated: false)
        onStatusAppearanceChanged?()
    }

    // MARK: - Persistence

    private func persistImmediately() {
        pendingPersistenceSave?.cancel()
        pendingPersistenceSave = nil
        store.save(state.snapshot)
    }

    private func scheduleDebouncedPersistence() {
        pendingPersistenceSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPersistenceSave = nil
            self.store.save(self.state.snapshot)
        }
        pendingPersistenceSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func flushPersistence() {
        if pendingPersistenceSave != nil {
            pendingPersistenceSave?.cancel()
            pendingPersistenceSave = nil
            store.save(state.snapshot)
        }
    }

    // MARK: - Observers & Debouncing

    private func installObservers() {
        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleScreenSync(delay: 0.08)
            }
        }
        notificationTokens.append(screenToken)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeNames: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in wakeNames {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleScreenSync(delay: 0.12)
                }
            }
            workspaceTokens.append(token)
        }

        let themeToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleAppearanceRefresh()
            }
        }
        distributedTokens.append(themeToken)

        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.scheduleAppearanceRefresh()
            }
        }
    }

    private func scheduleScreenSync(delay: TimeInterval) {
        pendingScreenSync?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingScreenSync = nil
            self.state.updateDisplays(Self.captureOnlineDisplays())
            self.rebuildWindows(forceDisplay: true)
            self.applyOverlays(animated: false)
            self.onStatusAppearanceChanged?()
        }
        pendingScreenSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleAppearanceRefresh() {
        pendingAppearanceSync?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingAppearanceSync = nil
            let nextDark = Self.currentSystemIsDark()
            guard nextDark != self.state.isDarkAppearance else { return }
            self.state.isDarkAppearance = nextDark
            self.applyOverlays(animated: true)
            self.onStatusAppearanceChanged?()
        }
        pendingAppearanceSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func syncHotKeyRegistration() {
        hotKeyManager.configure(enabled: state.snapshot.hotKeyEnabled, binding: state.snapshot.hotKeyBinding)
        hotKeyError = hotKeyManager.lastError
    }

    // MARK: - Overlay Windows

    static func captureOnlineDisplays() -> [DisplayDescriptor] {
        let mainScreenID = NSScreen.main.flatMap(Self.displayID(for:))
        var result: [DisplayDescriptor] = []
        for screen in NSScreen.screens {
            guard let displayID = Self.displayID(for: screen) else { continue }
            let frame = screen.frame
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let isMain = displayID == mainScreenID || (mainScreenID == nil && result.isEmpty)
            result.append(
                DisplayDescriptor(
                    id: displayID,
                    name: screen.localizedName,
                    logicalWidth: Int(frame.width.rounded()),
                    logicalHeight: Int(frame.height.rounded()),
                    scaleFactor: Double(screen.backingScaleFactor),
                    isBuiltIn: isBuiltIn,
                    isMain: isMain
                )
            )
        }
        return result
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func currentSystemIsDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func overlayColor(for tint: DimmingTint) -> NSColor {
        let components = tint.components
        return NSColor(
            srgbRed: CGFloat(components.red),
            green: CGFloat(components.green),
            blue: CGFloat(components.blue),
            alpha: 1.0
        )
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: true,
            screen: screen
        )
        window.level = desktopLevel
        window.backgroundColor = overlayColor(for: state.snapshot.tint)
        window.alphaValue = 0
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.canHide = false
        window.isExcludedFromWindowsMenu = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)
        return window
    }

    private func rebuildWindows(forceDisplay: Bool) {
        var seenIDs = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let displayID = Self.displayID(for: screen) else { continue }
            seenIDs.insert(displayID)
            if let existing = windows[displayID] {
                existing.level = desktopLevel
                existing.setFrame(screen.frame, display: forceDisplay && existing.isVisible)
            } else {
                windows[displayID] = makeWindow(for: screen)
            }
        }
        let staleIDs = windows.keys.filter { !seenIDs.contains($0) }
        for staleID in staleIDs {
            animationTokens.removeValue(forKey: staleID)
            if let staleWindow = windows.removeValue(forKey: staleID) {
                staleWindow.orderOut(nil)
                staleWindow.close()
            }
        }
    }

    private func applyOverlays(animated: Bool) {
        let color = overlayColor(for: state.snapshot.tint)
        for (displayID, window) in windows {
            let decision = state.decision(for: displayID)
            let nextToken = (animationTokens[displayID] ?? 0) &+ 1
            animationTokens[displayID] = nextToken

            window.level = desktopLevel
            window.backgroundColor = color

            if decision.shouldShowWindow {
                let targetAlpha = CGFloat(decision.targetAlpha)
                if !window.isVisible {
                    window.alphaValue = animated ? 0 : targetAlpha
                    window.orderFrontRegardless()
                } else {
                    window.orderFrontRegardless()
                }
                if animated {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.28
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        context.allowsImplicitAnimation = true
                        window.animator().alphaValue = targetAlpha
                    }
                } else {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0
                        window.animator().alphaValue = targetAlpha
                    }
                    window.alphaValue = targetAlpha
                }
            } else {
                if !window.isVisible && window.alphaValue <= CGFloat(DimmingBounds.visibilityEpsilon) {
                    continue
                }
                if animated {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.24
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        context.allowsImplicitAnimation = true
                        window.animator().alphaValue = 0
                    }, completionHandler: { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self, self.animationTokens[displayID] == nextToken else { return }
                            if let currentWindow = self.windows[displayID],
                               currentWindow.alphaValue <= CGFloat(DimmingBounds.visibilityEpsilon) {
                                currentWindow.orderOut(nil)
                            }
                        }
                    })
                } else {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0
                        window.animator().alphaValue = 0
                    }
                    window.alphaValue = 0
                    window.orderOut(nil)
                }
            }
        }
    }
}
