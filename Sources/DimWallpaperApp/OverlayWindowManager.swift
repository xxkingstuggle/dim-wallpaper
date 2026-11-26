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
    private var focusAnimationTokens: [CGDirectDisplayID: UInt64] = [:]
    private var lastFocusFingerprints: [CGDirectDisplayID: FocusDisplayRenderFingerprint] = [:]
    private var focusTargetResolver: FocusTargetResolver
    private var focusPollTimer: Timer?
    private var focusMouseUpMonitor: Any?
    private var pendingFastClickCheck: DispatchWorkItem?
    private var pendingSettleClickCheck: DispatchWorkItem?
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
        refreshFocusOverlays(animated: false, forceUpdate: true)
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
            refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
        }
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setDisplayIncluded(_ displayID: UInt32, included: Bool) {
        let shouldExclude = !included
        guard state.isDisplayExcluded(displayID) != shouldExclude else { return }
        state.setDisplayExcluded(displayID, excluded: shouldExclude)
        applyOverlays(animated: true, durationOverride: 0.07)
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
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
            refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
        } else {
            isFocusPausedByExcludedApp = false
            hidePooledFocusOverlays(animated: true, isManualAction: true)
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
        refreshFocusOverlays(animated: false, forceUpdate: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func applyFocusPreset(_ preset: FocusPreset) {
        state.applyFocusPreset(preset)
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
        syncFocusPollingTimer()
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setFocusTint(_ value: FocusTintOption) {
        guard state.snapshot.focusTint != value else { return }
        state.setFocusTint(value)
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setFocusScope(_ value: FocusScope) {
        guard state.snapshot.focusScope != value else { return }
        state.setFocusScope(value)
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setDimMenuBar(_ value: Bool) {
        guard state.snapshot.dimMenuBar != value else { return }
        state.setDimMenuBar(value)
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setDimDock(_ value: Bool) {
        guard state.snapshot.dimDock != value else { return }
        state.setDimDock(value)
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func applyFocusSystemBarPreset(_ preset: FocusSystemBarPreset) {
        state.applyFocusSystemBarPreset(preset)
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
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
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
        scheduleDebouncedPersistence()
        onStatusAppearanceChanged?()
    }

    func setPauseFocusOnFullscreen(_ value: Bool) {
        guard state.snapshot.pauseFocusOnFullscreen != value else { return }
        state.setPauseFocusOnFullscreen(value)
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
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
        refreshFocusOverlays(animated: true, forceUpdate: true, isManualAction: true)
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
        refreshFocusOverlays(animated: false, forceUpdate: true)
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
                self?.refreshFocusOverlays(animated: true, forceUpdate: true)
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
            self.refreshFocusOverlays(animated: false, forceUpdate: true)
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
            self.refreshFocusOverlays(animated: false, forceUpdate: false)
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
        refreshFocusOverlays(animated: true, forceUpdate: false)
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
                        self?.refreshFocusOverlays(animated: false, forceUpdate: false)
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
                        self?.scheduleMouseClickFocusChecks()
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
        pendingFastClickCheck?.cancel()
        pendingFastClickCheck = nil
        pendingSettleClickCheck?.cancel()
        pendingSettleClickCheck = nil
    }

    private func scheduleMouseClickFocusChecks() {
        guard isStarted, state.isFocusGloballyActive, !isScreenAsleep else { return }
        pendingFastClickCheck?.cancel()
        pendingSettleClickCheck?.cancel()

        let fastWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingFastClickCheck = nil
            self.refreshFocusOverlays(animated: true, forceUpdate: false)
        }
        let settleWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSettleClickCheck = nil
            self.refreshFocusOverlays(animated: false, forceUpdate: false)
        }
        pendingFastClickCheck = fastWork
        pendingSettleClickCheck = settleWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: fastWork)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: settleWork)
    }

    private func refreshFocusOverlays(animated: Bool, forceUpdate: Bool, isManualAction: Bool = false) {
        guard isStarted else { return }

        guard state.isFocusGloballyActive, !isScreenAsleep else {
            if isFocusPausedByExcludedApp {
                isFocusPausedByExcludedApp = false
                onStatusAppearanceChanged?()
            }
            hidePooledFocusOverlays(animated: animated && !isScreenAsleep, isManualAction: isManualAction)
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
            hidePooledFocusOverlays(animated: animated, isManualAction: isManualAction)
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
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration: TimeInterval
        if animated {
            duration = isManualAction
                ? state.snapshot.focusTransitionSpeed.resolvedManualDuration(reduceMotion: reduceMotion)
                : state.snapshot.focusTransitionSpeed.resolvedDuration(reduceMotion: reduceMotion)
        } else {
            duration = 0.0
        }

        for plan in plans {
            let fingerprint = FocusDisplayRenderFingerprint(
                placement: plan.placement,
                mainRect: plan.partition.mainRect,
                menuBarStripRect: plan.partition.menuBarStripRect,
                dockStripRects: plan.partition.dockStripRects,
                targetAlpha: plan.targetAlpha,
                tint: resolvedTint
            )

            if !forceUpdate, lastFocusFingerprints[plan.displayID] == fingerprint {
                continue
            }
            lastFocusFingerprints[plan.displayID] = fingerprint

            guard let screen = screensByID[plan.displayID] else { continue }
            applyFocusPlan(plan, on: screen, color: color, duration: duration)
        }
    }

    private func applyFocusPlan(
        _ plan: FocusDisplayPlan,
        on screen: NSScreen,
        color: NSColor,
        duration: TimeInterval
    ) {
        let displayID = plan.displayID
        let nextToken = (focusAnimationTokens[displayID] ?? 0) &+ 1
        focusAnimationTokens[displayID] = nextToken

        guard plan.shouldShow else {
            guard let group = focusGroups[displayID] else { return }
            fadeOutAndHideFocusGroup(group, displayID: displayID, token: nextToken, duration: duration)
            return
        }

        let group = focusGroups[displayID] ?? {
            let created = FocusDisplayOverlayGroup(
                mainWindow: makeFocusWindow(for: screen, frame: plan.partition.mainRect, level: focusNormalLevel, color: color)
            )
            focusGroups[displayID] = created
            return created
        }()

        let targetAlpha = CGFloat(plan.targetAlpha)

        let mainWindow = group.mainWindow
        mainWindow.level = focusNormalLevel
        mainWindow.backgroundColor = color
        if plan.partition.mainRect.width > FocusBounds.minimumStripThickness,
           plan.partition.mainRect.height > FocusBounds.minimumStripThickness {
            if !mainWindow.frame.equalTo(plan.partition.mainRect) {
                mainWindow.setFrame(plan.partition.mainRect, display: false)
            }
            let wasVisible = mainWindow.isVisible
            if !wasVisible {
                mainWindow.alphaValue = duration > 0 ? 0 : targetAlpha
            }
            switch plan.placement {
            case .orderBelow(let windowNumber):
                mainWindow.order(.below, relativeTo: windowNumber)
            case .orderFrontNormal:
                mainWindow.orderFrontRegardless()
            case .hidden:
                mainWindow.orderOut(nil)
            }
            animateWindowAlpha(mainWindow, to: targetAlpha, duration: duration)
        } else {
            mainWindow.alphaValue = 0
            mainWindow.orderOut(nil)
        }

        if let menuBarRect = plan.partition.menuBarStripRect {
            let menuWindow = group.menuBarWindow ?? makeFocusWindow(
                for: screen,
                frame: menuBarRect,
                level: focusMenuBarLevel,
                color: color
            )
            group.menuBarWindow = menuWindow
            menuWindow.level = focusMenuBarLevel
            menuWindow.backgroundColor = color
            if !menuWindow.frame.equalTo(menuBarRect) {
                menuWindow.setFrame(menuBarRect, display: false)
            }
            if !menuWindow.isVisible {
                menuWindow.alphaValue = duration > 0 ? 0 : targetAlpha
            }
            menuWindow.orderFrontRegardless()
            animateWindowAlpha(menuWindow, to: targetAlpha, duration: duration)
        } else if let existingMenuWindow = group.menuBarWindow {
            existingMenuWindow.alphaValue = 0
            existingMenuWindow.orderOut(nil)
        }

        let desiredDockRects = plan.partition.dockStripRects
        let maxPooledDockWindows = max(4, desiredDockRects.count)
        while group.dockWindows.count > maxPooledDockWindows {
            let extra = group.dockWindows.removeLast()
            extra.alphaValue = 0
            extra.orderOut(nil)
            extra.close()
        }
        if desiredDockRects.count < group.dockWindows.count {
            for index in desiredDockRects.count..<group.dockWindows.count {
                let unusedWindow = group.dockWindows[index]
                unusedWindow.alphaValue = 0
                unusedWindow.orderOut(nil)
            }
        }
        for (index, dockRect) in desiredDockRects.enumerated() {
            let dockWindow: NSWindow
            if index < group.dockWindows.count {
                dockWindow = group.dockWindows[index]
            } else {
                let created = makeFocusWindow(for: screen, frame: dockRect, level: focusDockLevel, color: color)
                group.dockWindows.append(created)
                dockWindow = created
            }
            dockWindow.level = focusDockLevel
            dockWindow.backgroundColor = color
            if !dockWindow.frame.equalTo(dockRect) {
                dockWindow.setFrame(dockRect, display: false)
            }
            if !dockWindow.isVisible {
                dockWindow.alphaValue = duration > 0 ? 0 : targetAlpha
            }
            dockWindow.orderFrontRegardless()
            animateWindowAlpha(dockWindow, to: targetAlpha, duration: duration)
        }
    }

    private func hidePooledFocusOverlays(animated: Bool, isManualAction: Bool = false) {
        guard !focusGroups.isEmpty else {
            lastFocusFingerprints.removeAll()
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration: TimeInterval
        if animated {
            duration = isManualAction
                ? state.snapshot.focusTransitionSpeed.resolvedManualDuration(reduceMotion: reduceMotion)
                : state.snapshot.focusTransitionSpeed.resolvedDuration(reduceMotion: reduceMotion)
        } else {
            duration = 0.0
        }
        for (displayID, group) in focusGroups {
            let nextToken = (focusAnimationTokens[displayID] ?? 0) &+ 1
            focusAnimationTokens[displayID] = nextToken
            lastFocusFingerprints.removeValue(forKey: displayID)
            fadeOutAndHideFocusGroup(group, displayID: displayID, token: nextToken, duration: duration)
        }
    }

    private func fadeOutAndHideFocusGroup(
        _ group: FocusDisplayOverlayGroup,
        displayID: CGDirectDisplayID,
        token: UInt64,
        duration: TimeInterval
    ) {
        let visibleWindows = group.allWindows.filter { $0.isVisible || $0.alphaValue > CGFloat(FocusBounds.visibilityEpsilon) }
        let allWindows = group.allWindows
        if visibleWindows.isEmpty {
            for window in allWindows {
                window.alphaValue = 0
                window.orderOut(nil)
            }
            return
        }
        if duration <= 0.001 {
            for window in allWindows {
                window.alphaValue = 0
                window.orderOut(nil)
            }
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            for window in visibleWindows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.focusAnimationTokens[displayID] == token else { return }
                for window in allWindows {
                    window.alphaValue = 0
                    window.orderOut(nil)
                }
            }
        })
    }

    private func removeFocusGroup(for displayID: CGDirectDisplayID) {
        focusAnimationTokens[displayID] = (focusAnimationTokens[displayID] ?? 0) &+ 1
        lastFocusFingerprints.removeValue(forKey: displayID)
        guard let group = focusGroups.removeValue(forKey: displayID) else { return }
        for window in group.allWindows {
            window.alphaValue = 0
            window.orderOut(nil)
            window.close()
        }
    }

    private func tearDownAllFocusOverlays() {
        let displayIDs = Array(focusGroups.keys)
        for displayID in displayIDs {
            removeFocusGroup(for: displayID)
        }
        focusGroups.removeAll()
        focusAnimationTokens.removeAll()
        lastFocusFingerprints.removeAll()
    }

    private func animateWindowAlpha(_ window: NSWindow, to targetAlpha: CGFloat, duration: TimeInterval) {
        if duration > 0.001 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
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
    }

    private func makeFocusWindow(
        for screen: NSScreen,
        frame: CGRect,
        level: NSWindow.Level,
        color: NSColor
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: true,
            screen: screen
        )
        window.level = level
        window.backgroundColor = color
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

@MainActor
private final class FocusDisplayOverlayGroup {
    let mainWindow: NSWindow
    var menuBarWindow: NSWindow?
    var dockWindows: [NSWindow] = []

    init(mainWindow: NSWindow) {
        self.mainWindow = mainWindow
    }

    var allWindows: [NSWindow] {
        var list: [NSWindow] = [mainWindow]
        if let menuBarWindow {
            list.append(menuBarWindow)
        }
        list.append(contentsOf: dockWindows)
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
}
