//
//  AudioInputInfo.swift
//  AuralKit
//
//  Created by Ifrit on 10/8/25.
//

import Foundation
import AudioToolbox

#if os(iOS)
import AVFoundation
#elseif os(macOS)
import AVFAudio
import CoreAudio
#endif

/// Describes the active hardware input route that is feeding `SpeechSession`.
public struct AudioInputInfo: Sendable, CustomStringConvertible {
    /// Human-readable name reported by the system (for example “AirPods Pro”).
    public let portName: String
    /// Symbol configuration to display alongside the name in UI.
    public let portIcon: String
    /// Stable identifier for the port so changes can be tracked.
    public let uid: String
    /// Metadata for each available channel on the port.
    public let channels: [ChannelInfo]

#if os(iOS)
    public let portType: AVAudioSession.Port
    public let hasHardwareVoiceCallProcessing: Bool
    public let dataSources: [DataSourceInfo]?
    public let selectedDataSource: DataSourceInfo?
    public let preferredDataSource: DataSourceInfo?
#elseif os(macOS)
    public let manufacturer: String?
    public let nominalSampleRate: Double?
#endif

    public var description: String {
        var lines = [
            "AudioInputInfo:",
            "\(portName)",
            "UID: \(uid)"
        ]

        if !channels.isEmpty {
            lines.append("Channels: \(channels.count)")
            for channel in channels {
                lines.append("  • \(channel.channelName) (ch \(channel.channelNumber))")
            }
        }

#if os(iOS)
        lines.append("Port Type: \(portType.rawValue)")
        lines.append("Hardware Voice Processing: \(hasHardwareVoiceCallProcessing ? "✓" : "✗")")

        if let selectedDataSource {
            var dataSourceLine = "Data Source: \(selectedDataSource.dataSourceName)"
            if let location = selectedDataSource.location {
                dataSourceLine += " (\(location.rawValue))"
            }
            lines.append(dataSourceLine)

            if let pattern = selectedDataSource.selectedPolarPattern {
                lines.append("  Polar Pattern: \(pattern.rawValue)")
            }
        }

        if let dataSources, dataSources.count > 1 {
            lines.append("Available Sources: \(dataSources.count)")
        }
#elseif os(macOS)
        if let manufacturer, !manufacturer.isEmpty {
            lines.append("Manufacturer: \(manufacturer)")
        }
        if let nominalSampleRate {
            lines.append("Sample Rate: \(String(format: "%.0f Hz", nominalSampleRate))")
        }
#endif

        return lines.joined(separator: "\n")
    }

    /// Metadata describing a single channel on the active input port.
    public struct ChannelInfo: Sendable {
        /// Label such as “Input 1”.
        public let channelName: String
        /// 1-based channel number reported by Core Audio / AVAudioSession.
        public let channelNumber: Int
        /// Port UID that owns this channel.
        public let owningPortUID: String
        /// Core Audio channel label, when available.
        public let channelLabel: AudioChannelLabel
    }

#if os(iOS)
    /// Summary of a specific iOS audio data source (built-in mic, beam pattern, etc.).
    public struct DataSourceInfo: Sendable {
        public let dataSourceID: NSNumber
        public let dataSourceName: String
        public let location: AVAudioSession.Location?
        public let orientation: AVAudioSession.Orientation?
        public let supportedPolarPatterns: [AVAudioSession.PolarPattern]?
        public let selectedPolarPattern: AVAudioSession.PolarPattern?
        public let preferredPolarPattern: AVAudioSession.PolarPattern?
    }
#endif
}

#if os(iOS)
public extension AudioInputInfo {
    /// Creates a new `AudioInputInfo` from an `AVAudioSessionPortDescription`.
    /// - Parameter portDescription: The port supplied by `AVAudioSession.currentRoute`.
    init(from portDescription: AVAudioSessionPortDescription) {
        let portType = portDescription.portType
        let portName = portDescription.portName
        let uid = portDescription.uid
        let channels = portDescription.channels?.map { channel -> ChannelInfo in
            ChannelInfo(
                channelName: channel.channelName,
                channelNumber: channel.channelNumber,
                owningPortUID: channel.owningPortUID,
                channelLabel: channel.channelLabel
            )
        } ?? []

        let dataSourceMapper: (AVAudioSessionDataSourceDescription) -> DataSourceInfo = { source in
            DataSourceInfo(
                dataSourceID: source.dataSourceID,
                dataSourceName: source.dataSourceName,
                location: source.location,
                orientation: source.orientation,
                supportedPolarPatterns: source.supportedPolarPatterns,
                selectedPolarPattern: source.selectedPolarPattern,
                preferredPolarPattern: source.preferredPolarPattern
            )
        }

        self.init(
            portName: portName,
            portIcon: AudioInputInfo.iconName(for: portDescription),
            uid: uid,
            channels: channels,
            portType: portType,
            hasHardwareVoiceCallProcessing: portDescription.hasHardwareVoiceCallProcessing,
            dataSources: portDescription.dataSources?.map(dataSourceMapper),
            selectedDataSource: portDescription.selectedDataSource.map(dataSourceMapper),
            preferredDataSource: portDescription.preferredDataSource.map(dataSourceMapper)
        )
    }

    private static func iconName(for port: AVAudioSessionPortDescription) -> String {
        let normalizedName = port.portName.lowercased()

        // Check for specific device names first
        if let specificIcon = specificDeviceIcon(for: normalizedName) {
            return specificIcon
        }

        // Fall back to port type
        return iconForPortType(port.portType, normalizedName: normalizedName)
    }

    private static func specificDeviceIcon(for normalizedName: String) -> String? {
        if normalizedName.contains("pro") {
            return "airpods.pro"
        } else if normalizedName.contains("max") {
            return "airpods.max"
        } else if normalizedName.contains("airpods") {
            return "airpods"
        }
        return nil
    }

    private static func iconForPortType(_ type: AVAudioSession.Port, normalizedName: String) -> String {
        switch type {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return bluetoothDeviceIcon(for: normalizedName)
        case .builtInMic:
            return "mic"
        case .headsetMic:
            return "headphones"
        case .lineIn:
            return "cable.connector"
        case .usbAudio:
            return "music.microphone"
        default:
            return "mic"
        }
    }

    private static func bluetoothDeviceIcon(for normalizedName: String) -> String {
        if normalizedName.contains("beats") {
            return "beats.headphones"
        } else if normalizedName.contains("headphone") || normalizedName.contains("headset") {
            return "headphones"
        } else {
            return "airpods.gen4"
        }
    }
}
#elseif os(macOS)
public extension AudioInputInfo {
    /// Errors emitted while querying Core Audio for device metadata on macOS.
    enum AudioInputInfoError: Error, LocalizedError {
        case audioHardwareError(OSStatus, selector: AudioObjectPropertySelector)

        public var errorDescription: String? {
            switch self {
            case let .audioHardwareError(status, selector):
                return "Audio hardware error \(status) for selector \(selector)"
            }
        }
    }

    /// Returns metadata for the current default input, or `nil` if no input is available.
    /// - Throws: `AudioInputInfoError` when Core Audio queries fail.
    static func current() throws -> AudioInputInfo? {
        guard let deviceID = try defaultInputDeviceID() else {
            return nil
        }

        return try AudioInputInfo(deviceID: deviceID)
    }

    private init(deviceID: AudioObjectID) throws {
        let uid = try Self.copyStringProperty(
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal,
            deviceID: deviceID
        ) ?? "\(deviceID)"
        let name = try Self.copyStringProperty(
            selector: kAudioDevicePropertyDeviceNameCFString,
            scope: kAudioObjectPropertyScopeGlobal,
            deviceID: deviceID
        ) ?? "Unknown Device"
        let manufacturer = try Self.copyStringProperty(
            selector: kAudioDevicePropertyDeviceManufacturerCFString,
            scope: kAudioObjectPropertyScopeGlobal,
            deviceID: deviceID
        )
        let nominalSampleRate = try Self.nominalSampleRate(for: deviceID)
        let channelCount = try Self.inputChannelCount(for: deviceID)

        let channelInfos = (0..<channelCount).map { index in
            ChannelInfo(
                channelName: "Input \(index + 1)",
                channelNumber: index + 1,
                owningPortUID: uid,
                channelLabel: kAudioChannelLabel_Unknown
            )
        }

        self.portName = name
        self.portIcon = Self.iconName(for: name)
        self.uid = uid
        self.channels = channelInfos
        self.manufacturer = manufacturer
        self.nominalSampleRate = nominalSampleRate
    }

    private static func defaultInputDeviceID() throws -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(0)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw AudioInputInfoError.audioHardwareError(status, selector: address.mSelector)
        }

        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    private static func copyStringProperty(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        deviceID: AudioObjectID
    ) throws -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        if status != noErr {
            throw AudioInputInfoError.audioHardwareError(status, selector: selector)
        }

        guard dataSize > 0 else {
            return nil
        }

        var value: CFString?
        status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, pointer)
        }
        if status != noErr {
            throw AudioInputInfoError.audioHardwareError(status, selector: selector)
        }

        return value as String?
    }

    private static func nominalSampleRate(for deviceID: AudioObjectID) throws -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Double(0)
        var dataSize = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &value)
        if status != noErr {
            throw AudioInputInfoError.audioHardwareError(status, selector: address.mSelector)
        }
        return value
    }

    private static func inputChannelCount(for deviceID: AudioObjectID) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        )
        if status != noErr {
            throw AudioInputInfoError.audioHardwareError(
                status,
                selector: address.mSelector
            )
        }

        guard dataSize > 0 else {
            return 0
        }

        let bufferPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferPointer)
        if status != noErr {
            throw AudioInputInfoError.audioHardwareError(status, selector: address.mSelector)
        }

        let audioBufferList = bufferPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var totalChannels = 0
        for audioBuffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            totalChannels += Int(audioBuffer.mNumberChannels)
        }

        return totalChannels
    }

    private static func iconName(for name: String) -> String {
        let normalized = name.lowercased()
        if normalized.contains("usb") {
            return "cable.connector"
        } else if normalized.contains("headset") || normalized.contains("headphone") {
            return "headphones"
        } else if normalized.contains("bluetooth") {
            return "wave.3.left"
        }
        return "mic"
    }
}
#endif
