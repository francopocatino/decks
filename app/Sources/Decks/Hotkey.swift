import Carbon
import Foundation

enum HotkeyOption: String, CaseIterable, Identifiable {
    case off, ctrlOptSpace, optCmdN, ctrlOptD

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .ctrlOptSpace: "⌃⌥ Space"
        case .optCmdN: "⌥⌘ N"
        case .ctrlOptD: "⌃⌥ D"
        }
    }

    var key: (code: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .ctrlOptSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .optCmdN: (UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey))
        case .ctrlOptD: (UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey))
        }
    }
}

// Carbon RegisterEventHotKey: system-wide, no accessibility prompt.
@MainActor
@Observable
final class HotkeyManager {
    private static let signature = OSType(0x4443_4B53)

    private(set) var registrationFailed = false
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    @ObservationIgnored private var action: (() -> Void)?

    func apply(_ option: HotkeyOption, action: @escaping () -> Void) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        self.action = action
        registrationFailed = false
        guard let key = option.key else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(key.code, key.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        hotKeyRef = ref
        registrationFailed = status != noErr || ref == nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { manager.action?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
