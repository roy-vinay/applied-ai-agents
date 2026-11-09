import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts that work while another app (the call) is in front.
/// Carbon hot keys need no special permission.
final class HotKeys {
    private var refs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKeys.actions[id.id]?() }
            return noErr
        }, 1, &spec, me, &handler)
    }

    /// Registers Control+Option plus a key.
    func register(_ keyCode: Int, _ action: @escaping () -> Void) {
        let id = UInt32(actions.count + 1)
        actions[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5343_4852), id: id) // "SCHR"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("Second Chair: could not register hot key \(keyCode): \(status)") }
        refs.append(ref)
    }
}
