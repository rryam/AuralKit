//
//  AudioInputInfo.swift
//  AuralKit
//
//  Created by Ifrit on 10/8/25.
//

import AVFoundation

public struct AudioInputInfo: Sendable, CustomStringConvertible {
    public let portType: AVAudioSession.Port
    public let portName: String
    public let portIcon: String
    public let uid: String
    public let hasHardwareVoiceCallProcessing: Bool
    public let channels: [ChannelInfo]
    public let dataSources: [DataSourceInfo]?
    public let selectedDataSource: DataSourceInfo?
    public let preferredDataSource: DataSourceInfo?

    public var description: String {
        var desc = """
        AudioInputInfo:
        \(portName) (\(portType.rawValue))
        UID: \(uid)
        Hardware Voice Processing: \(hasHardwareVoiceCallProcessing ? "✓" : "✗")
        """

        if !channels.isEmpty {
            desc += "\nChannels: \(channels.count)"
            for channel in channels {
                desc += "\n  • \(channel.channelName) (ch \(channel.channelNumber))"
            }
        }

        if let selectedDataSource {
            desc += "\nData Source: \(selectedDataSource.dataSourceName)"
            if let location = selectedDataSource.location {
                desc += " (\(location.rawValue))"
            }
            if let pattern = selectedDataSource.selectedPolarPattern {
                desc += "\n  Polar Pattern: \(pattern.rawValue)"
            }
        }

        if let dataSources, dataSources.count > 1 {
            desc += "\nAvailable Sources: \(dataSources.count)"
        }

        return desc
    }

    public struct ChannelInfo: Sendable {
        public let channelName: String
        public let channelNumber: Int
        public let owningPortUID: String
        public let channelLabel: AudioChannelLabel
    }
    
    public struct DataSourceInfo: Sendable {
        public let dataSourceID: NSNumber
        public let dataSourceName: String
        public let location: AVAudioSession.Location?
        public let orientation: AVAudioSession.Orientation?
        public let supportedPolarPatterns: [AVAudioSession.PolarPattern]?
        public let selectedPolarPattern: AVAudioSession.PolarPattern?
        public let preferredPolarPattern: AVAudioSession.PolarPattern?
    }
    
    public init(from portDescription: AVAudioSessionPortDescription) {
        self.portType = portDescription.portType
        self.portName = portDescription.portName
        self.portIcon = AudioInputInfo.audioPortToIcon(portDescription)
        self.uid = portDescription.uid
        self.hasHardwareVoiceCallProcessing = portDescription.hasHardwareVoiceCallProcessing
        self.channels = portDescription.channels?.map { channel in
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

        self.dataSources = portDescription.dataSources?.map(dataSourceMapper)
        self.selectedDataSource = portDescription.selectedDataSource.map(dataSourceMapper)
        self.preferredDataSource = portDescription.preferredDataSource.map(dataSourceMapper)
    }
}

// UI Helper
extension AudioInputInfo {
#if os(iOS)
    private static func audioPortToIcon(_ port: AVAudioSessionPortDescription) -> String {
        let portName = port.portName.lowercased()
        let portType = port.portType
        
        if portName.contains("pro") {
            return "airpods.pro"
        } else if portName.contains("max") {
            return "airpods.max"
        } else if portName.contains("airpods") {
            return "airpods"
        }
        
        switch portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            if portName.contains("beats") {
                return "beats.headphones"
            } else if portName.contains("headphone") || portName.contains("headset") {
                return "headphones"
            } else {
                return "airpods.gen4"
            }
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
#endif
}
