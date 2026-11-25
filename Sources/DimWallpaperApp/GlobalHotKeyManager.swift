import Carbon
import Foundation
#if canImport(DimWallpaperCore)
import DimWallpaperCore
#endif

enum HotKeySlot: UInt32, CaseIterable, Hashable {
    case wallpaper = 1
    case focus = 2
}

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == GlobalHotKeyManager.signature,
          let slot = HotKeySlot(rawValue: hotKeyID.id) else {
        return OSStatus(eventNotHandledErr)
    }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handlePressed(slot: slot)
    }
    return noErr
}

@MainActor
final class GlobalHotKeyManager {
    nonisolated static let signature: OSType = 0x44494D57

    private var handlers: [HotKeySlot: () -> Void] = [:]
    private(set) var lastErrors: [HotKeySlot: String] = [:]

    private var hotKeyRefs: [HotKeySlot: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    func setHandler(for slot: HotKeySlot, handler: @escaping () -> Void) {
        handlers[slot] = handler
    }

    func lastError(for slot: HotKeySlot) -> String? {
        lastErrors[slot]
    }

    func configure(slot: HotKeySlot, enabled: Bool, binding: HotKeyBinding) {
        unregister(slot: slot)
        lastErrors.removeValue(forKey: slot)

        guard enabled else { return }
        guard binding.isValid else {
            lastErrors[slot] = "快捷键配置无效，未启用全局热键。"
            return
        }

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let userData = Unmanaged.passUnretained(self).toOpaque()
            let installStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyEventHandler,
                1,
                &eventType,
                userData,
                &eventHandlerRef
            )
            guard installStatus == noErr else {
                lastErrors[slot] = "无法安装快捷键事件处理器（错误码 \(installStatus)）。"
                return
            }
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        var registeredRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredRef
        )
        if registerStatus == noErr, let registeredRef {
            hotKeyRefs[slot] = registeredRef
            lastErrors.removeValue(forKey: slot)
        } else {
            lastErrors[slot] = "快捷键 \(binding.displayLabel) 已被其他应用占用（错误码 \(registerStatus)）。"
        }
    }

    func shutdown() {
        for slot in HotKeySlot.allCases {
            unregister(slot: slot)
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        lastErrors.removeAll()
    }

    fileprivate func handlePressed(slot: HotKeySlot) {
        handlers[slot]?()
    }

    private func unregister(slot: HotKeySlot) {
        if let currentRef = hotKeyRefs.removeValue(forKey: slot) {
            UnregisterEventHotKey(currentRef)
        }
    }
}
