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
    @Published private(set) var focusHotKeyError: String?
    @Published private(set) var loginStatus: SMAppService.Status
    @Published private(set) var loginError: String?
    @Published private(set) var trackedExternalApp: FocusAppIdentity?
    @Published private(set) var isFocusPausedByExcludedApp = false

    var onStatusAppearanceChanged: (() -> Void)?

    let store: PreferencesStore
    let launchOptions: LaunchOptions
    let loginController = LoginItemController()

    private let hotKeyManager = GlobalHotKeyManager()
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var animationTokens: [CGDirectDisplayID: UInt64] = [:]
    private var focusGroups: [CGDirectDisplayID: FocusDisplayOverlayGroup] = [:]
    private var lastFocusFingerprints: [CGDirectDisplayID: FocusDisplayRenderFingerprint] = [:]
    private var focusTargetResolver: FocusTargetResolver
    private var focusPollTimer: Timer?
    private var focusMouseUpMonitor: Any?
    private var pendingClickChecks: [DispatchWorkItem] = []
    private var isScreenAsleep = false
    private var appearanceObserver: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var pendingScreenSync: DispatchWorkItem?
    private var pendingAppearanceSync: DispatchWorkItem?
    private var pendingPersistenceSave: DispatchWorkItem?
    private var isStarted = false
    private let selfPID: Int32 = ProcessInfo.processInfo.processIdentifier

    private let desktopLevel: NSWindow.Level = {
        let baseLevel = CGWindowLevelForKey(.desktopWindow)
        let iconLevel = CGWindowLevelForKey(.desktopIconWindow)
        let resolved = OverlayWindowPolicy.resolvedWindowLevel(desktopLevel: baseLevel, desktopIconLevel: iconLevel)
        assert(OverlayWindowPolicy.isStrictlyBetweenDesktopAndIcons(level: resolved, desktopLevel: baseLevel, desktopIconLevel: iconLevel))
        return NSWindow.Level(rawValue: resolved)
    }()

    private let focusNormalLevel = NSWindow.Level(rawValue: FocusWindowLevels.normalFocusLevel)

    private let focusMenuBarLevel: NSWindow.Level = {
        let statusBar = max(CGWindowLevelForKey(.statusWindow), CGWindowLevelForKey(.mainMenuWindow))
        let popUpMenu = CGWindowLevelForKey(.popUpMenuWindow)
        let resolved = FocusWindowLevels.menuBarOverlayLevel(statusBarLevel: statusBar, popUpMenuLevel: popUpMenu)
        return NSWindow.Level(rawValue: resolved)
    }()

    private let focusDockLevel: NSWindow.Level = {
        let dock = CGWindowLevelForKey(.dockWindow)
        let mainMenu = CGWindowLevelForKey(.mainMenuWindow)
        let resolved = FocusWindowLevels.dockOverlayLevel(dockLevel: dock, mainMenuLevel: mainMenu)
        return NSWindow.Level(rawValue: resolved)
    }()

    init(launchOptions: LaunchOptions) {
        self.launchOptions = launchOptions
        let preferences = PreferencesStore(suiteName: launchOptions.defaultsSuiteName)
        self.store = preferences
        let loadedSnapshot = preferences.load()
        let initialSnapshot = launchOptions.applyingOverrides(to: loadedSnapshot)
        if launchOptions.defaultsSuiteName != nil, launchOptions.hasFocusOverrides {
            preferences.save(initialSnapshot)
        }
        let initialDisplays = Self.captureOnlineDisplays()
        self.state = DimmingEngineState(
            snapshot: initialSnapshot,
            isDarkAppearance: Self.currentSystemIsDark(),
            displays: initialDisplays
        )
        self.loginStatus = loginController.status
        self.focusTargetResolver = FocusTargetResolver(selfPID: ProcessInfo.processInfo.processIdentifier)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        state.isDarkAppearance = Self.currentSystemIsDark()
        state.updateDisplays(Self.captureOnlineDisplays())

        hotKeyManager.setHandler(for: .wallpaper) { [weak self] in
            self?.toggleEnabled()
        }
        hotKeyManager.setHandler(for: .focus) { [weak self] in
            self?.toggleFocusEnabled()
        }
        syncHotKeyRegistration()

        loginController.setupOnFirstLaunchIfNeeded(store: store, disabled: launchOptions.disableLoginItemSetup)
        refreshLoginStatus()

        captureExternalFrontmostAppIfNeeded()
        installObservers()
        rebuildWindows(forceDisplay: true)
        applyOverlays(animated: false)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        syncFocusPollingTimer()
        onStatusAppearanceChanged?()
    }

    func shutdown() {
        pendingScreenSync?.cancel()
        pendingScreenSync = nil
        pendingAppearanceSync?.cancel()
        pendingAppearanceSync = nil
        stopFocusMonitors()
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

        tearDownAllFocusOverlays()
        isStarted = false
    }

    // MARK: - User Actions

    func setEnabled(_ value: Bool) {
        guard state.snapshot.enabled != value else { return }
        state.setEnabled(value)
        applyOverlays(animated: true, durationOverride: 0.07)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func toggleEnabled() {
        setEnabled(!state.snapshot.enabled)
    }

    func setIntensity(_ value: Double) {
        let clamped = DimmingBounds.clampedIntensity(value)
        guard abs(state.snapshot.intensity - clamped) > 0.0001 else { return }
        state.setIntensity(clamped)
        applyOverlays(animated: false)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func applyPreset(_ preset: DimmingPreset) {
        state.applyPreset(preset)
        applyOverlays(animated: true, durationOverride: 0.07)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setDarkOnly(_ value: Bool) {
        guard state.snapshot.darkOnly != value else { return }
        state.setDarkOnly(value)
        applyOverlays(animated: true, durationOverride: 0.07)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setTint(_ value: DimmingTint) {
        guard state.snapshot.tint != value else { return }
        state.setTint(value)
        applyOverlays(animated: true, durationOverride: 0.07)
        if state.snapshot.focusTint == .followWallpaper {
            refreshFocusOverlays(style: .transition, forceUpdate: true)
        }
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setDisplayIncluded(_ displayID: UInt32, included: Bool) {
        let shouldExclude = !included
        guard state.isDisplayExcluded(displayID) != shouldExclude else { return }
        state.setDisplayExcluded(displayID, excluded: shouldExclude)
        applyOverlays(animated: true, durationOverride: 0.07)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setHotKeyEnabled(_ value: Bool) {
        guard state.snapshot.hotKeyEnabled != value else { return }
        state.setHotKeyEnabled(value)
        syncHotKeyRegistration()
        scheduleDebouncedPersistence()
    }

    func setFocusEnabled(_ value: Bool) {
        guard state.snapshot.focusEnabled != value else { return }
        state.setFocusEnabled(value)
        if value {
            refreshFocusOverlays(style: .transition, forceUpdate: true)
        } else {
            isFocusPausedByExcludedApp = false
            hidePooledFocusOverlays(style: .transition)
        }
        syncFocusPollingTimer()
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func toggleFocusEnabled() {
        setFocusEnabled(!state.snapshot.focusEnabled)
    }

    func setFocusIntensity(_ value: Double) {
        let clamped = FocusBounds.clampedIntensity(value)
        guard abs(state.snapshot.focusIntensity - clamped) > 0.0001 else { return }
        state.setFocusIntensity(clamped)
        refreshFocusOverlays(style: .interactiveScrub, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func applyFocusPreset(_ preset: FocusPreset) {
        state.applyFocusPreset(preset)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        syncFocusPollingTimer()
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setFocusTint(_ value: FocusTintOption) {
        guard state.snapshot.focusTint != value else { return }
        state.setFocusTint(value)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setFocusScope(_ value: FocusScope) {
        guard state.snapshot.focusScope != value else { return }
        state.setFocusScope(value)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setDimMenuBar(_ value: Bool) {
        guard state.snapshot.dimMenuBar != value else { return }
        state.setDimMenuBar(value)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setDimDock(_ value: Bool) {
        guard state.snapshot.dimDock != value else { return }
        state.setDimDock(value)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func applyFocusSystemBarPreset(_ preset: FocusSystemBarPreset) {
        state.applyFocusSystemBarPreset(preset)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func toggleDimSystemBarsTogether() {
        let bothEnabled = state.snapshot.dimMenuBar && state.snapshot.dimDock
        applyFocusSystemBarPreset(bothEnabled ? .keepSystemBars : .dimAll)
    }

    func setFocusMultiDisplayPolicy(_ value: FocusMultiDisplayPolicy) {
        guard state.snapshot.focusMultiDisplayPolicy != value else { return }
        state.setFocusMultiDisplayPolicy(value)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setPauseFocusOnFullscreen(_ value: Bool) {
        guard state.snapshot.pauseFocusOnFullscreen != value else { return }
        state.setPauseFocusOnFullscreen(value)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setFocusEdgeFeather(_ value: FocusEdgeFeather) {
        guard state.snapshot.focusEdgeFeather != value else { return }
        state.setFocusEdgeFeather(value)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setFocusTransitionSpeed(_ value: FocusTransitionSpeed) {
        guard state.snapshot.focusTransitionSpeed != value else { return }
        state.setFocusTransitionSpeed(value)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setFocusExcludedApp(_ bundleID: String, excluded: Bool) {
        let currentlyExcluded = state.isAppExcludedFromFocus(bundleID: bundleID)
        guard currentlyExcluded != excluded else { return }
        state.setFocusExcludedApp(bundleID, excluded: excluded)
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        syncFocusPollingTimer()
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func toggleTrackedAppFocusExclusion() {
        guard let bundleID = trackedExternalApp?.bundleIdentifier, !bundleID.isEmpty else { return }
        let excluded = state.isAppExcludedFromFocus(bundleID: bundleID)
        setFocusExcludedApp(bundleID, excluded: !excluded)
    }

    func setFocusHotKeyEnabled(_ value: Bool) {
        guard state.snapshot.focusHotKeyEnabled != value else { return }
        state.setFocusHotKeyEnabled(value)
        syncHotKeyRegistration()
        scheduleDebouncedPersistence()
    }

    func recordFrontmostAppFast() {
        focusTargetResolver.recordFrontmostAppFast(Self.currentFrontmostAppIdentity())
        if trackedExternalApp != focusTargetResolver.lastExternalFrontmostApp {
            trackedExternalApp = focusTargetResolver.lastExternalFrontmostApp
        }
    }

    func captureExternalFrontmostAppIfNeeded() {
        let current = Self.currentFrontmostAppIdentity()
        let observedWindows = Self.captureOnScreenWindows()
        let screenGeometries = Self.captureScreenGeometries()
        _ = focusTargetResolver.resolve(
            currentFrontmost: current,
            excludedBundleIDs: state.snapshot.focusExcludedBundleIDs,
            observedWindows: observedWindows,
            screens: screenGeometries,
            fallbackAppProvider: Self.appIdentity(forPID:)
        )
        if trackedExternalApp != focusTargetResolver.lastExternalFrontmostApp {
            trackedExternalApp = focusTargetResolver.lastExternalFrontmostApp
        }
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
        refreshFocusOverlays(style: .transition, forceUpdate: true)
        syncFocusPollingTimer()
        onStatusAppearanceChanged?()
    }

    func refreshDisplaysIfChanged() {
        let latestDisplays = Self.captureOnlineDisplays()
        if latestDisplays != state.displays {
            refreshDisplaysNow()
        }
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
        ]
        for name in wakeNames {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreensDidWake()
                }
            }
            workspaceTokens.append(token)
        }

        let spaceToken = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleScreenSync(delay: 0.12)
                self?.refreshFocusOverlays(style: .transition, forceUpdate: true)
            }
        }
        workspaceTokens.append(spaceToken)

        let appStateNames: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in appStateNames {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleFrontmostApplicationChanged()
                }
            }
            workspaceTokens.append(token)
        }

        let sleepToken = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreensDidSleep()
            }
        }
        workspaceTokens.append(sleepToken)

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
            self.refreshFocusOverlays(style: .transition, forceUpdate: true)
            self.syncFocusPollingTimer()
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
            self.applyOverlays(animated: true, durationOverride: 0.16)
            self.refreshFocusOverlays(style: .transition, forceUpdate: false)
            self.onStatusAppearanceChanged?()
        }
        pendingAppearanceSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func syncHotKeyRegistration() {
        hotKeyManager.configure(
            slot: .wallpaper,
            enabled: state.snapshot.hotKeyEnabled,
            binding: state.snapshot.hotKeyBinding
        )
        hotKeyManager.configure(
            slot: .focus,
            enabled: state.snapshot.focusHotKeyEnabled,
            binding: state.snapshot.focusHotKeyBinding
        )
        hotKeyError = hotKeyManager.lastError(for: .wallpaper)
        focusHotKeyError = hotKeyManager.lastError(for: .focus)
    }

    // MARK: - Focus Mode Lifecycle & Window Hosting

    private func handleFrontmostApplicationChanged() {
        guard state.isFocusGloballyActive, !isScreenAsleep else {
            recordFrontmostAppFast()
            return
        }
        refreshFocusOverlays(style: .transition, forceUpdate: false)
        scheduleStagedFocusChecks(delays: [0.10, 0.22, 0.38])
        syncFocusPollingTimer()
    }

    private func handleScreensDidSleep() {
        isScreenAsleep = true
        stopFocusMonitors()
        tearDownAllFocusOverlays()
    }

    private func handleScreensDidWake() {
        isScreenAsleep = false
        scheduleScreenSync(delay: 0.16)
    }

    private func syncFocusPollingTimer() {
        let shouldPoll = isStarted
            && state.isFocusGloballyActive
            && !isScreenAsleep
            && !isFocusPausedByExcludedApp
        if shouldPoll {
            if focusPollTimer == nil {
                let timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshFocusOverlays(style: .transition, forceUpdate: false)
                    }
                }
                timer.tolerance = 0.3
                focusPollTimer = timer
            }
            if focusMouseUpMonitor == nil {
                focusMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
                    matching: [.leftMouseUp, .rightMouseUp]
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.scheduleStagedFocusChecks(delays: [0.02, 0.10, 0.22, 0.38])
                    }
                }
            }
        } else {
            stopFocusMonitors()
        }
    }

    private func stopFocusMonitors() {
        focusPollTimer?.invalidate()
        focusPollTimer = nil
        if let monitor = focusMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            focusMouseUpMonitor = nil
        }
        cancelPendingClickChecks()
    }

    private func cancelPendingClickChecks() {
        for item in pendingClickChecks {
            item.cancel()
        }
        pendingClickChecks.removeAll()
    }

    private func scheduleStagedFocusChecks(delays: [TimeInterval]) {
        guard isStarted, state.isFocusGloballyActive, !isScreenAsleep else { return }
        cancelPendingClickChecks()

        var scheduled: [DispatchWorkItem] = []
        scheduled.reserveCapacity(delays.count)
        for delay in delays {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.refreshFocusOverlays(style: .transition, forceUpdate: false)
            }
            scheduled.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        pendingClickChecks = scheduled
    }

    private func refreshFocusOverlays(style: FocusRefreshStyle, forceUpdate: Bool) {
        guard isStarted else { return }

        guard state.isFocusGloballyActive, !isScreenAsleep else {
            if isFocusPausedByExcludedApp {
                isFocusPausedByExcludedApp = false
                onStatusAppearanceChanged?()
            }
            hidePooledFocusOverlays(style: isScreenAsleep ? .immediate : style)
            return
        }

        let currentFrontmost = Self.currentFrontmostAppIdentity()
        let observedWindows = Self.captureOnScreenWindows()
        let screenGeometries = Self.captureScreenGeometries()
        let targetResolution = focusTargetResolver.resolve(
            currentFrontmost: currentFrontmost,
            excludedBundleIDs: state.snapshot.focusExcludedBundleIDs,
            observedWindows: observedWindows,
            screens: screenGeometries,
            fallbackAppProvider: Self.appIdentity(forPID:)
        )
        if trackedExternalApp != focusTargetResolver.lastExternalFrontmostApp {
            trackedExternalApp = focusTargetResolver.lastExternalFrontmostApp
        }

        let pausedByExclusion: Bool
        let targetPID: Int32?
        switch targetResolution {
        case .active(let identity):
            pausedByExclusion = false
            targetPID = identity.pid
        case .pausedByExcludedApp:
            pausedByExclusion = true
            targetPID = nil
        case .unavailable:
            pausedByExclusion = false
            targetPID = nil
        }
        if isFocusPausedByExcludedApp != pausedByExclusion {
            isFocusPausedByExcludedApp = pausedByExclusion
            onStatusAppearanceChanged?()
        }

        guard !pausedByExclusion else {
            hidePooledFocusOverlays(style: style)
            return
        }

        let plans = FocusWindowOrderPlanner.plan(
            screens: screenGeometries,
            windows: observedWindows,
            targetPID: targetPID,
            selfPID: selfPID,
            isEnabled: state.isFocusGloballyActive,
            intensity: state.snapshot.focusIntensity,
            scope: state.snapshot.focusScope,
            dimMenuBar: state.snapshot.dimMenuBar,
            dimDock: state.snapshot.dimDock,
            multiDisplayPolicy: state.snapshot.focusMultiDisplayPolicy,
            excludedDisplayIDs: state.snapshot.excludedDisplayIDs,
            pauseFocusOnFullscreen: state.snapshot.pauseFocusOnFullscreen,
            excludedBundleIDs: state.snapshot.focusExcludedBundleIDs
        )

        let onlineIDs = Set(screenGeometries.map(\.displayID))
        let staleFocusIDs = focusGroups.keys.filter { !onlineIDs.contains($0) }
        for staleID in staleFocusIDs {
            removeFocusGroup(for: staleID)
        }

        let screensByID = Self.screensByDisplayID()
        let resolvedTint = state.resolvedFocusTint
        let color = overlayColor(for: resolvedTint)
        let edgeFeather = state.snapshot.focusEdgeFeather
        let dimMenuBar = state.snapshot.dimMenuBar
        let speed = state.snapshot.focusTransitionSpeed
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        for plan in plans {
            let fingerprint = FocusDisplayRenderFingerprint(
                placement: plan.placement,
                mainRect: plan.partition.mainRect,
                menuBarStripRect: plan.partition.menuBarStripRect,
                dockStripRects: plan.partition.dockStripRects,
                targetAlpha: plan.targetAlpha,
                tint: resolvedTint,
                edgeFeather: edgeFeather,
                dimMenuBar: dimMenuBar
            )

            if !forceUpdate, lastFocusFingerprints[plan.displayID] == fingerprint {
                continue
            }
            lastFocusFingerprints[plan.displayID] = fingerprint

            guard let screen = screensByID[plan.displayID] else { continue }
            applyFocusPlan(
                plan,
                on: screen,
                color: color,
                edgeFeather: edgeFeather,
                dimMenuBar: dimMenuBar,
                style: style,
                speed: speed,
                reduceMotion: reduceMotion
            )
        }
    }

    private func applyFocusPlan(
        _ plan: FocusDisplayPlan,
        on screen: NSScreen,
        color: NSColor,
        edgeFeather: FocusEdgeFeather,
        dimMenuBar: Bool,
        style: FocusRefreshStyle,
        speed: FocusTransitionSpeed,
        reduceMotion: Bool
    ) {
        let displayID = plan.displayID

        guard plan.shouldShow else {
            guard let group = focusGroups[displayID] else { return }
            fadeOutAndHideFocusGroup(group, style: style, speed: speed, reduceMotion: reduceMotion)
            return
        }

        let featherStops = FocusEdgeFeatherCurve.gradientStops(
            feather: edgeFeather,
            dimMenuBar: dimMenuBar,
            mainRectHeight: plan.partition.mainRect.height
        )

        let group = focusGroups[displayID] ?? {
            let (mainWindow, backdropView) = makeFeatheredFocusMainWindow(
                for: screen,
                frame: plan.partition.mainRect,
                level: focusNormalLevel,
                color: color,
                stops: featherStops
            )
            let created = FocusDisplayOverlayGroup(
                mainSlot: FocusOverlaySlot(window: mainWindow),
                mainBackdropView: backdropView
            )
            focusGroups[displayID] = created
            return created
        }()

        let targetAlpha = CGFloat(plan.targetAlpha)
        let mainSlot = group.mainSlot
        let mainWindow = mainSlot.window
        mainWindow.level = focusNormalLevel
        mainWindow.backgroundColor = .clear

        if plan.partition.mainRect.width > FocusBounds.minimumStripThickness,
           plan.partition.mainRect.height > FocusBounds.minimumStripThickness {
            if !mainWindow.frame.equalTo(plan.partition.mainRect) {
                mainWindow.setFrame(plan.partition.mainRect, display: false)
            }
            group.mainBackdropView.frame = NSRect(origin: .zero, size: plan.partition.mainRect.size)
            group.mainBackdropView.update(color: color, stops: featherStops)
            group.mainBackdropView.layoutSubtreeIfNeeded()

            prepareSlotBeforeOrdering(mainSlot, targetAlpha: targetAlpha, style: style, speed: speed, reduceMotion: reduceMotion)
            switch plan.placement {
            case .orderBelow(let windowNumber):
                mainWindow.order(.below, relativeTo: windowNumber)
            case .orderFrontNormal:
                mainWindow.orderFrontRegardless()
            case .hidden:
                mainWindow.orderOut(nil)
            }
            animateSlotToVisible(mainSlot, targetAlpha: targetAlpha, style: style, speed: speed, reduceMotion: reduceMotion)
        } else {
            fadeOutSlot(mainSlot, style: style, speed: speed, reduceMotion: reduceMotion)
        }

        if let menuBarRect = plan.partition.menuBarStripRect {
            let menuSlot = group.menuBarSlot ?? {
                let window = makeSolidFocusWindow(
                    for: screen,
                    frame: menuBarRect,
                    level: focusMenuBarLevel,
                    color: color
                )
                let slot = FocusOverlaySlot(window: window)
                group.menuBarSlot = slot
                return slot
            }()
            let menuWindow = menuSlot.window
            menuWindow.level = focusMenuBarLevel
            menuWindow.backgroundColor = color
            if !menuWindow.frame.equalTo(menuBarRect) {
                menuWindow.setFrame(menuBarRect, display: false)
            }
            prepareSlotBeforeOrdering(menuSlot, targetAlpha: targetAlpha, style: style, speed: speed, reduceMotion: reduceMotion)
            menuWindow.orderFrontRegardless()
            animateSlotToVisible(menuSlot, targetAlpha: targetAlpha, style: style, speed: speed, reduceMotion: reduceMotion)
        } else if let existingMenuSlot = group.menuBarSlot {
            fadeOutSlot(existingMenuSlot, style: style, speed: speed, reduceMotion: reduceMotion)
        }

        let desiredDockRects = plan.partition.dockStripRects
        let maxPooledDockWindows = max(4, desiredDockRects.count)
        while group.dockSlots.count > maxPooledDockWindows {
            let extra = group.dockSlots.removeLast()
            extra.token &+= 1
            extra.targetVisible = false
            extra.targetAlpha = 0
            extra.isAnimating = false
            extra.window.alphaValue = 0
            extra.window.orderOut(nil)
            extra.window.close()
        }
        if desiredDockRects.count < group.dockSlots.count {
            for index in desiredDockRects.count..<group.dockSlots.count {
                fadeOutSlot(group.dockSlots[index], style: style, speed: speed, reduceMotion: reduceMotion)
            }
        }
        for (index, dockRect) in desiredDockRects.enumerated() {
            let dockSlot: FocusOverlaySlot
            if index < group.dockSlots.count {
                dockSlot = group.dockSlots[index]
            } else {
                let created = FocusOverlaySlot(
                    window: makeSolidFocusWindow(for: screen, frame: dockRect, level: focusDockLevel, color: color)
                )
                group.dockSlots.append(created)
                dockSlot = created
            }
            let dockWindow = dockSlot.window
            dockWindow.level = focusDockLevel
            dockWindow.backgroundColor = color
            if !dockWindow.frame.equalTo(dockRect) {
                dockWindow.setFrame(dockRect, display: false)
            }
            prepareSlotBeforeOrdering(dockSlot, targetAlpha: targetAlpha, style: style, speed: speed, reduceMotion: reduceMotion)
            dockWindow.orderFrontRegardless()
            animateSlotToVisible(dockSlot, targetAlpha: targetAlpha, style: style, speed: speed, reduceMotion: reduceMotion)
        }
    }

    private func hidePooledFocusOverlays(style: FocusRefreshStyle) {
        guard !focusGroups.isEmpty else {
            lastFocusFingerprints.removeAll()
            return
        }
        let speed = state.snapshot.focusTransitionSpeed
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (displayID, group) in focusGroups {
            lastFocusFingerprints.removeValue(forKey: displayID)
            fadeOutAndHideFocusGroup(group, style: style, speed: speed, reduceMotion: reduceMotion)
        }
    }

    private func fadeOutAndHideFocusGroup(
        _ group: FocusDisplayOverlayGroup,
        style: FocusRefreshStyle,
        speed: FocusTransitionSpeed,
        reduceMotion: Bool
    ) {
        for slot in group.allSlots {
            fadeOutSlot(slot, style: style, speed: speed, reduceMotion: reduceMotion)
        }
    }

    private func prepareSlotBeforeOrdering(
        _ slot: FocusOverlaySlot,
        targetAlpha: CGFloat,
        style: FocusRefreshStyle,
        speed: FocusTransitionSpeed,
        reduceMotion: Bool
    ) {
        guard !slot.window.isVisible else { return }
        let shouldAnimate = style == .transition && speed.resolvedFadeInDuration(reduceMotion: reduceMotion) > 0.001
        slot.window.alphaValue = shouldAnimate ? 0 : targetAlpha
    }

    private func animateSlotToVisible(
        _ slot: FocusOverlaySlot,
        targetAlpha: CGFloat,
        style: FocusRefreshStyle,
        speed: FocusTransitionSpeed,
        reduceMotion: Bool
    ) {
        if style == .interactiveScrub || style == .immediate {
            slot.token &+= 1
            slot.targetVisible = true
            slot.targetAlpha = targetAlpha
            slot.isAnimating = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                slot.window.animator().alphaValue = targetAlpha
            }
            slot.window.alphaValue = targetAlpha
            return
        }

        let isAlreadyTargetingSameState = slot.targetVisible
            && abs(slot.targetAlpha - targetAlpha) <= 0.001
            && (slot.isAnimating || (slot.window.isVisible && abs(slot.window.alphaValue - targetAlpha) <= 0.005))
        if isAlreadyTargetingSameState {
            return
        }

        let duration: TimeInterval
        if !slot.targetVisible || targetAlpha >= slot.targetAlpha {
            duration = speed.resolvedFadeInDuration(reduceMotion: reduceMotion)
        } else {
            duration = speed.resolvedFadeOutDuration(reduceMotion: reduceMotion)
        }

        slot.token &+= 1
        let capturedToken = slot.token
        slot.targetVisible = true
        slot.targetAlpha = targetAlpha

        guard duration > 0.001 else {
            slot.isAnimating = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                slot.window.animator().alphaValue = targetAlpha
            }
            slot.window.alphaValue = targetAlpha
            return
        }

        slot.isAnimating = true
        let timingFunction = mediaTimingFunction(for: speed.timingCurve)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = timingFunction
            context.allowsImplicitAnimation = true
            slot.window.animator().alphaValue = targetAlpha
        }, completionHandler: { [weak slot] in
            Task { @MainActor [weak slot] in
                guard let slot, slot.token == capturedToken else { return }
                slot.isAnimating = false
            }
        })
    }

    private func fadeOutSlot(
        _ slot: FocusOverlaySlot,
        style: FocusRefreshStyle,
        speed: FocusTransitionSpeed,
        reduceMotion: Bool
    ) {
        let isHiddenNow = !slot.window.isVisible && slot.window.alphaValue <= CGFloat(FocusBounds.visibilityEpsilon)
        if isHiddenNow {
            slot.token &+= 1
            slot.targetVisible = false
            slot.targetAlpha = 0
            slot.isAnimating = false
            slot.window.alphaValue = 0
            slot.window.orderOut(nil)
            return
        }

        if style == .transition && !slot.targetVisible && slot.isAnimating {
            return
        }

        let duration = (style == .transition)
            ? speed.resolvedFadeOutDuration(reduceMotion: reduceMotion)
            : 0.0

        slot.token &+= 1
        let capturedToken = slot.token
        slot.targetVisible = false
        slot.targetAlpha = 0

        guard duration > 0.001 else {
            slot.isAnimating = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                slot.window.animator().alphaValue = 0
            }
            slot.window.alphaValue = 0
            slot.window.orderOut(nil)
            return
        }

        slot.isAnimating = true
        let timingFunction = mediaTimingFunction(for: speed.timingCurve)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = timingFunction
            context.allowsImplicitAnimation = true
            slot.window.animator().alphaValue = 0
        }, completionHandler: { [weak slot] in
            Task { @MainActor [weak slot] in
                guard let slot, slot.token == capturedToken else { return }
                slot.isAnimating = false
                slot.window.alphaValue = 0
                slot.window.orderOut(nil)
            }
        })
    }

    private func mediaTimingFunction(for curve: FocusTimingCurve) -> CAMediaTimingFunction {
        switch curve {
        case let .cubicBezier(c1x, c1y, c2x, c2y):
            return CAMediaTimingFunction(controlPoints: c1x, c1y, c2x, c2y)
        case .linear:
            return CAMediaTimingFunction(name: .linear)
        case .easeInEaseOut:
            return CAMediaTimingFunction(name: .easeInEaseOut)
        }
    }

    private func removeFocusGroup(for displayID: CGDirectDisplayID) {
        lastFocusFingerprints.removeValue(forKey: displayID)
        guard let group = focusGroups.removeValue(forKey: displayID) else { return }
        for slot in group.allSlots {
            slot.token &+= 1
            slot.targetVisible = false
            slot.targetAlpha = 0
            slot.isAnimating = false
            slot.window.alphaValue = 0
            slot.window.orderOut(nil)
            slot.window.close()
        }
    }

    private func tearDownAllFocusOverlays() {
        let displayIDs = Array(focusGroups.keys)
        for displayID in displayIDs {
            removeFocusGroup(for: displayID)
        }
        focusGroups.removeAll()
        lastFocusFingerprints.removeAll()
    }

    private func makeFeatheredFocusMainWindow(
        for screen: NSScreen,
        frame: CGRect,
        level: NSWindow.Level,
        color: NSColor,
        stops: [FocusEdgeFeatherStop]
    ) -> (NSWindow, FocusBackdropView) {
        let window = makeBaseFocusWindow(for: screen, frame: frame, level: level, backgroundColor: .clear)
        let backdropView = FocusBackdropView(frame: NSRect(origin: .zero, size: frame.size))
        backdropView.update(color: color, stops: stops)
        window.contentView = backdropView
        backdropView.layoutSubtreeIfNeeded()
        return (window, backdropView)
    }

    private func makeSolidFocusWindow(
        for screen: NSScreen,
        frame: CGRect,
        level: NSWindow.Level,
        color: NSColor
    ) -> NSWindow {
        makeBaseFocusWindow(for: screen, frame: frame, level: level, backgroundColor: color)
    }

    private func makeBaseFocusWindow(
        for screen: NSScreen,
        frame: CGRect,
        level: NSWindow.Level,
        backgroundColor: NSColor
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: true,
            screen: screen
        )
        window.level = level
        window.backgroundColor = backgroundColor
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
        window.setFrame(frame, display: false)
        return window
    }

    private static func currentFrontmostAppIdentity() -> FocusAppIdentity? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return makeAppIdentity(from: app)
    }

    private static func appIdentity(forPID pid: Int32) -> FocusAppIdentity? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return makeAppIdentity(from: app)
    }

    private static func makeAppIdentity(from app: NSRunningApplication) -> FocusAppIdentity {
        let name = app.localizedName ?? app.bundleIdentifier ?? "PID \(app.processIdentifier)"
        return FocusAppIdentity(
            pid: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            localizedName: name,
            isRegularActivationPolicy: app.activationPolicy == .regular
        )
    }

    private static func screensByDisplayID() -> [CGDirectDisplayID: NSScreen] {
        var map: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let displayID = displayID(for: screen) {
                map[displayID] = screen
            }
        }
        return map
    }

    private static func captureScreenGeometries() -> [ScreenGeometry] {
        let screens = NSScreen.screens
        var result: [ScreenGeometry] = []
        for (index, screen) in screens.enumerated() {
            guard let displayID = displayID(for: screen) else { continue }
            result.append(
                ScreenGeometry(
                    displayID: displayID,
                    frame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    isPrimary: index == 0,
                    safeAreaTopInset: screen.safeAreaInsets.top
                )
            )
        }
        return result
    }

    private static func captureOnScreenWindows() -> [ObservedWindowInfo] {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var result: [ObservedWindowInfo] = []
        result.reserveCapacity(rawList.count)
        var bundleIDByPID: [Int32: String?] = [:]

        for entry in rawList {
            guard let windowNumber = (entry[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            let isOnScreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            let ownerName = entry[kCGWindowOwnerName as String] as? String
            let ownerBundleID: String?
            if let cached = bundleIDByPID[ownerPID] {
                ownerBundleID = cached
            } else {
                let resolved = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
                bundleIDByPID[ownerPID] = resolved
                ownerBundleID = resolved
            }
            result.append(
                ObservedWindowInfo(
                    windowNumber: windowNumber,
                    ownerPID: ownerPID,
                    layer: layer,
                    alpha: alpha,
                    cgBounds: cgBounds,
                    isOnScreen: isOnScreen,
                    ownerName: ownerName,
                    ownerBundleIdentifier: ownerBundleID
                )
            )
        }
        return result
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

    private func applyOverlays(animated: Bool, durationOverride: TimeInterval? = nil) {
        let color = overlayColor(for: state.snapshot.tint)
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fadeInDuration = durationOverride ?? 0.08
        let fadeOutDuration = durationOverride ?? 0.08
        for (displayID, window) in windows {
            let decision = state.decision(for: displayID)
            let nextToken = (animationTokens[displayID] ?? 0) &+ 1
            animationTokens[displayID] = nextToken

            window.level = desktopLevel
            window.backgroundColor = color

            if decision.shouldShowWindow {
                let targetAlpha = CGFloat(decision.targetAlpha)
                if !window.isVisible {
                    window.alphaValue = shouldAnimate ? 0 : targetAlpha
                    window.orderFrontRegardless()
                } else {
                    window.orderFrontRegardless()
                }
                if shouldAnimate {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = fadeInDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
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
                if shouldAnimate {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = fadeOutDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
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

private enum FocusRefreshStyle {
    case transition
    case interactiveScrub
    case immediate
}

@MainActor
private final class FocusBackdropView: NSView {
    private let gradientLayer = CAGradientLayer()
    private var lastColor: NSColor?
    private var lastStops: [FocusEdgeFeatherStop] = []

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        configureLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.isGeometryFlipped = false
        layer?.backgroundColor = NSColor.clear.cgColor
        gradientLayer.isGeometryFlipped = false
        gradientLayer.type = .axial
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.frame = bounds
        gradientLayer.needsDisplayOnBoundsChange = true
        if gradientLayer.superlayer == nil {
            layer?.addSublayer(gradientLayer)
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        if let scale = window?.backingScaleFactor, scale > 0 {
            gradientLayer.contentsScale = scale
        }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let scale = window?.backingScaleFactor, scale > 0 {
            gradientLayer.contentsScale = scale
        }
        CATransaction.commit()
    }

    func update(color: NSColor, stops: [FocusEdgeFeatherStop]) {
        guard lastColor != color || lastStops != stops else { return }
        lastColor = color
        lastStops = stops

        let resolvedRGB = color.usingColorSpace(.sRGB) ?? color
        let red = resolvedRGB.redComponent
        let green = resolvedRGB.greenComponent
        let blue = resolvedRGB.blueComponent

        let cgColors: [CGColor] = stops.map { stop in
            NSColor(
                srgbRed: red,
                green: green,
                blue: blue,
                alpha: CGFloat(stop.opacityWeight)
            ).cgColor
        }
        let locations: [NSNumber] = stops.map { NSNumber(value: $0.location) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.colors = cgColors
        gradientLayer.locations = locations
        gradientLayer.frame = bounds
        CATransaction.commit()
    }
}

@MainActor
private final class FocusOverlaySlot {
    let window: NSWindow
    var targetVisible = false
    var targetAlpha: CGFloat = 0
    var isAnimating = false
    var token: UInt64 = 0

    init(window: NSWindow) {
        self.window = window
    }
}

@MainActor
private final class FocusDisplayOverlayGroup {
    let mainSlot: FocusOverlaySlot
    let mainBackdropView: FocusBackdropView
    var menuBarSlot: FocusOverlaySlot?
    var dockSlots: [FocusOverlaySlot] = []

    init(mainSlot: FocusOverlaySlot, mainBackdropView: FocusBackdropView) {
        self.mainSlot = mainSlot
        self.mainBackdropView = mainBackdropView
    }

    var allSlots: [FocusOverlaySlot] {
        var list: [FocusOverlaySlot] = [mainSlot]
        if let menuBarSlot {
            list.append(menuBarSlot)
        }
        list.append(contentsOf: dockSlots)
        return list
    }
}

private struct FocusDisplayRenderFingerprint: Equatable {
    let placement: FocusWindowPlacement
    let mainRect: CGRect
    let menuBarStripRect: CGRect?
    let dockStripRects: [CGRect]
    let targetAlpha: Double
    let tint: DimmingTint
    let edgeFeather: FocusEdgeFeather
    let dimMenuBar: Bool
}
