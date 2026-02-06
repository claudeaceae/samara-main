// aggregate-device: Create/destroy a multi-output aggregate audio device
//
// Creates a CoreAudio aggregate device combining multiple output devices.
// Used to send FaceTime call audio to both speakers (audible) and a
// virtual device (recordable).
//
// Usage:
//   aggregate-device create --name "Call Monitor" --devices "Mac mini Speakers" "Call Capture"
//   aggregate-device destroy --name "Call Monitor"
//   aggregate-device list

import Foundation
import CoreAudio

// MARK: - Audio Device Helpers

func getDeviceID(named name: String) -> AudioDeviceID? {
    var propertySize: UInt32 = 0
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &devices)

    for device in devices {
        var nameSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceName: CFString = "" as CFString
        let status = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &deviceName)
        if status == noErr && (deviceName as String) == name {
            return device
        }
    }
    return nil
}

func getDeviceUID(deviceID: AudioDeviceID) -> String? {
    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
    return status == noErr ? (uid as String) : nil
}

func listAllDevices() {
    var propertySize: UInt32 = 0
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &devices)

    for device in devices {
        var nameSize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceName: CFString = "" as CFString
        AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &deviceName)

        let uid = getDeviceUID(deviceID: device) ?? "?"

        // Check if output device
        var outputSize: UInt32 = 0
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(device, &outputAddress, 0, nil, &outputSize)
        let hasOutput = outputSize > UInt32(MemoryLayout<AudioBufferList>.size)

        // Check if input device
        var inputSize: UInt32 = 0
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(device, &inputAddress, 0, nil, &inputSize)
        let hasInput = inputSize > UInt32(MemoryLayout<AudioBufferList>.size)

        var types = [String]()
        if hasInput { types.append("input") }
        if hasOutput { types.append("output") }

        print("  \(deviceName as String) (ID: \(device), UID: \(uid)) [\(types.joined(separator: ", "))]")
    }
}

// MARK: - Aggregate Device

func createAggregateDevice(name: String, deviceNames: [String]) -> AudioDeviceID? {
    // Resolve device UIDs
    var subDevices = [[String: Any]]()
    for devName in deviceNames {
        guard let devID = getDeviceID(named: devName),
              let uid = getDeviceUID(deviceID: devID) else {
            FileHandle.standardError.write("Error: Device '\(devName)' not found\n".data(using: .utf8)!)
            return nil
        }
        subDevices.append([
            kAudioSubDeviceUIDKey as String: uid
        ])
        FileHandle.standardError.write("  Adding sub-device: \(devName) (UID: \(uid))\n".data(using: .utf8)!)
    }

    let aggregateUID = "com.samara.aggregate.\(name.replacingOccurrences(of: " ", with: "-").lowercased())"

    let description: [String: Any] = [
        kAudioAggregateDeviceNameKey as String: name,
        kAudioAggregateDeviceUIDKey as String: aggregateUID,
        kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
        kAudioAggregateDeviceIsPrivateKey as String: false,
        kAudioAggregateDeviceIsStackedKey as String: false  // multi-output, not stacked
    ]

    var aggregateDeviceID: AudioDeviceID = 0
    let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)

    if status != noErr {
        FileHandle.standardError.write("Error creating aggregate device: OSStatus \(status)\n".data(using: .utf8)!)
        return nil
    }

    return aggregateDeviceID
}

func destroyAggregateDevice(name: String) -> Bool {
    guard let deviceID = getDeviceID(named: name) else {
        FileHandle.standardError.write("Error: Device '\(name)' not found\n".data(using: .utf8)!)
        return false
    }

    let status = AudioHardwareDestroyAggregateDevice(deviceID)
    if status != noErr {
        FileHandle.standardError.write("Error destroying aggregate device: OSStatus \(status)\n".data(using: .utf8)!)
        return false
    }
    return true
}

// MARK: - Main

func printUsage() {
    print("""
    Usage:
      aggregate-device create --name "Device Name" --devices "Dev1" "Dev2" ...
      aggregate-device destroy --name "Device Name"
      aggregate-device list
    """)
}

let args = Array(CommandLine.arguments.dropFirst())

guard let action = args.first else {
    printUsage()
    exit(1)
}

switch action {
case "list":
    print("Audio devices:")
    listAllDevices()

case "create":
    var name: String?
    var devices = [String]()
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--name":
            i += 1
            if i < args.count { name = args[i] }
        case "--devices":
            i += 1
            while i < args.count && !args[i].hasPrefix("--") {
                devices.append(args[i])
                i += 1
            }
            continue
        default:
            break
        }
        i += 1
    }

    guard let deviceName = name, !devices.isEmpty else {
        FileHandle.standardError.write("Error: --name and --devices required\n".data(using: .utf8)!)
        printUsage()
        exit(1)
    }

    FileHandle.standardError.write("Creating aggregate device '\(deviceName)' with sub-devices: \(devices)\n".data(using: .utf8)!)
    if let deviceID = createAggregateDevice(name: deviceName, deviceNames: devices) {
        print("{\"name\":\"\(deviceName)\",\"deviceID\":\(deviceID),\"status\":\"created\"}")
    } else {
        exit(1)
    }

case "destroy":
    var name: String?
    var i = 1
    while i < args.count {
        if args[i] == "--name" {
            i += 1
            if i < args.count { name = args[i] }
        }
        i += 1
    }

    guard let deviceName = name else {
        FileHandle.standardError.write("Error: --name required\n".data(using: .utf8)!)
        exit(1)
    }

    if destroyAggregateDevice(name: deviceName) {
        print("{\"name\":\"\(deviceName)\",\"status\":\"destroyed\"}")
    } else {
        exit(1)
    }

default:
    printUsage()
    exit(1)
}
