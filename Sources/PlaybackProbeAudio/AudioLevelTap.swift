//
// The Core Audio call sequence here is derived from AudioCap by Guilherme
// Rambo, https://github.com/insidegui/AudioCap
// Copyright (c) 2024 Guilherme Rambo. Licensed under the BSD 2-Clause licence;
// see THIRD-PARTY-NOTICES.md at the root of this repository for the full text.
//

import AudioToolbox
import CoreAudio
import Foundation
import os

/// Reports the level of what the Mac is playing.
///
/// This is the audio oracle. It watches the sound leaving the machine, which is
/// the only evidence that does not come from the player itself: a player can
/// report `paused` while a second instance inside the same SDK keeps producing
/// sound, and nothing inside the application would notice.
///
/// Requires audio capture permission. The system asks for it the first time a
/// tap is created, and only for a signed application bundle, so the host has to
/// be an app rather than a bare executable.
public final class AudioLevelTap: @unchecked Sendable {
    /// What to listen to.
    public enum Source: Sendable, Equatable {
        /// Everything the Mac plays. Always works, and hears every other
        /// application too, so nothing else may make a sound during a test.
        case systemWide
        /// Specific audio processes, found through ``AudioProcess``.
        ///
        /// An application running in a simulator appears here under its own
        /// bundle identifier, but only while it runs and with a new object
        /// each launch, so whoever holds the tap has to follow it.
        case processes([AudioObjectID])
    }

    private let logger = Logger(subsystem: "com.github.ukitaka.PlaybackProbe", category: "audio")
    private let source: Source
    private let lock = NSLock()

    private var tapID = AudioObjectID.unknown
    private var aggregateDeviceID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    public init(source: Source = .systemWide) {
        self.source = source
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ioProcID != nil
    }

    /// Starts tapping and calls `onLevel` for every buffer the hardware plays.
    ///
    /// The callback runs on Core Audio's real-time thread. It must not block,
    /// allocate or take locks that anything slow holds.
    public func start(
        queue: DispatchQueue = DispatchQueue(label: "com.github.ukitaka.PlaybackProbe.audio"),
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard ioProcID == nil else { return }

        let description = makeTapDescription()
        var tapID = AudioObjectID.unknown
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID.isValid else {
            throw AudioTapError.tapCreationFailed(status)
        }
        self.tapID = tapID

        // The tap only produces audio through an aggregate device that carries
        // it. The real output device has to be the main sub-device, otherwise
        // the aggregate has no clock to run against.
        let outputDeviceID = try AudioObjectID.readDefaultSystemOutputDevice()
        let outputUID = try outputDeviceID.readDeviceUID()

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PlaybackProbe",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            // Private so the aggregate never appears in Sound preferences.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            // Without this the tap is created but never fed.
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]

        var aggregateDeviceID = AudioObjectID.unknown
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard status == noErr, aggregateDeviceID.isValid else {
            throw AudioTapError.aggregateDeviceCreationFailed(status)
        }
        self.aggregateDeviceID = aggregateDeviceID

        // Registered directly on the aggregate device. AVAudioEngine cannot be
        // pointed at a device carrying a tap: setting its current device
        // returns success and then quietly keeps reading the default input.
        var ioProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateDeviceID,
            queue
        ) { _, inputData, _, _, _ in
            onLevel(AudioLevel.rootMeanSquare(of: inputData))
        }
        guard status == noErr, let ioProcID else {
            throw AudioTapError.ioProcCreationFailed(status)
        }
        self.ioProcID = ioProcID

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            throw AudioTapError.deviceStartFailed(status)
        }

        logger.info("Audio tap running on aggregate device \(aggregateDeviceID, privacy: .public)")
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        if aggregateDeviceID.isValid {
            if let ioProcID {
                AudioDeviceStop(aggregateDeviceID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
                self.ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }

        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    private func makeTapDescription() -> CATapDescription {
        let description = switch source {
        case .systemWide:
            CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        case let .processes(objectIDs):
            CATapDescription(stereoMixdownOfProcesses: objectIDs)
        }
        description.uuid = UUID()
        // Left audible: silencing what is being measured would change the very
        // thing under test, and a person running this needs to hear it too.
        description.muteBehavior = .unmuted
        return description
    }
}
