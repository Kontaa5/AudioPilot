import CoreAudio

/// Dünne Hülle um die CoreAudio-Property-API. Keine eigene Logik – nur Apple-Aufrufe.
enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let global = kAudioObjectPropertyScopeGlobal
    static let output = kAudioObjectPropertyScopeOutput
    static let input = kAudioObjectPropertyScopeInput
    static let main = kAudioObjectPropertyElementMain

    static func addr(_ sel: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = global,
                     _ element: AudioObjectPropertyElement = main) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
    }

    static func has(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                    _ scope: AudioObjectPropertyScope = global,
                    _ element: AudioObjectPropertyElement = main) -> Bool {
        var a = addr(sel, scope, element)
        return AudioObjectHasProperty(obj, &a)
    }

    static func settable(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = global,
                         _ element: AudioObjectPropertyElement = main) -> Bool {
        var a = addr(sel, scope, element)
        guard AudioObjectHasProperty(obj, &a) else { return false }
        var ok: DarwinBoolean = false
        return AudioObjectIsPropertySettable(obj, &a, &ok) == noErr && ok.boolValue
    }

    static func get<T: BitwiseCopyable>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = global,
                       _ element: AudioObjectPropertyElement = main, initial: T) -> T? {
        var a = addr(sel, scope, element)
        var size = UInt32(MemoryLayout<T>.size)
        var v = initial
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func array<T: BitwiseCopyable>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = global, initial: T) -> [T] {
        var a = addr(sel, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var arr = [T](repeating: initial, count: Int(size) / MemoryLayout<T>.stride)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &arr) == noErr else { return [] }
        return arr
    }

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = global) -> String? {
        var a = addr(sel, scope)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var s: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &s) == noErr, let s else { return nil }
        return s.takeRetainedValue() as String
    }

    @discardableResult
    static func set<T: BitwiseCopyable>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = global,
                       _ element: AudioObjectPropertyElement = main, _ value: T) -> OSStatus {
        var a = addr(sel, scope, element)
        var v = value
        return AudioObjectSetPropertyData(obj, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    }

    static func listen(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ block: @escaping () -> Void) {
        var a = addr(sel)
        AudioObjectAddPropertyListenerBlock(obj, &a, .main) { _, _ in block() }
    }
}
