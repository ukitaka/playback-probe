//
// Derived from AudioCap by Guilherme Rambo, https://github.com/insidegui/AudioCap
// Copyright (c) 2024 Guilherme Rambo. Licensed under the BSD 2-Clause licence;
// see THIRD-PARTY-NOTICES.md at the root of this repository for the full text.
//
// Core Audio exposes everything through untyped property reads. These helpers
// wrap that in something callable, and are the part most easily got wrong: the
// selectors, scopes and qualifier sizes have to match exactly or the call fails
// in ways that do not say why.
//

import AudioToolbox
import CoreAudio
import Foundation

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool { self != Self.unknown }

    /// Every process Core Audio knows about, playing or not.
    static func readProcessList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(.system, &address, 0, nil, &dataSize)
        guard status == noErr else { throw AudioTapError.propertyReadFailed("process list size", status) }

        var identifiers = [AudioObjectID](
            repeating: .unknown,
            count: Int(dataSize) / MemoryLayout<AudioObjectID>.size
        )
        status = AudioObjectGetPropertyData(.system, &address, 0, nil, &dataSize, &identifiers)
        guard status == noErr else { throw AudioTapError.propertyReadFailed("process list", status) }

        return identifiers
    }

    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.read(
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            defaultValue: AudioDeviceID.unknown,
            label: "default output device"
        )
    }

    func readDeviceUID() throws -> String {
        try readString(kAudioDevicePropertyDeviceUID, label: "device UID")
    }

    func readProcessBundleID() -> String? {
        let value = try? readString(kAudioProcessPropertyBundleID, label: "process bundle identifier")
        return (value?.isEmpty ?? true) ? nil : value
    }

    func readProcessPID() -> pid_t? {
        try? read(kAudioProcessPropertyPID, defaultValue: pid_t(-1), label: "process identifier")
    }

    /// Whether the process is currently producing output, which is how a
    /// player is told apart from every other process on the machine.
    func readIsRunningOutput() -> Bool {
        let value: UInt32? = try? read(
            kAudioProcessPropertyIsRunningOutput,
            defaultValue: 0,
            label: "process output activity"
        )
        return value == 1
    }

    func read<Value>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        defaultValue: Value,
        label: String
    ) throws -> Value {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard status == noErr else { throw AudioTapError.propertyReadFailed("\(label) size", status) }

        var value = defaultValue
        status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, pointer)
        }
        guard status == noErr else { throw AudioTapError.propertyReadFailed(label, status) }

        return value
    }

    private func readString(_ selector: AudioObjectPropertySelector, label: String) throws -> String {
        try read(selector, defaultValue: "" as CFString, label: label) as String
    }
}

public enum AudioTapError: Error, CustomStringConvertible {
    case propertyReadFailed(String, OSStatus)
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    public var description: String {
        switch self {
        case let .propertyReadFailed(what, status):
            "Could not read the \(what) from Core Audio (status \(status))."
        case let .tapCreationFailed(status):
            """
            Could not create the audio tap (status \(status)). This usually means \
            audio capture permission was refused, or was never asked for because \
            the host is not a signed application bundle.
            """
        case let .aggregateDeviceCreationFailed(status):
            "Could not create the aggregate device carrying the tap (status \(status))."
        case let .ioProcCreationFailed(status):
            "Could not register the audio callback (status \(status))."
        case let .deviceStartFailed(status):
            "Could not start the aggregate device (status \(status))."
        }
    }
}
