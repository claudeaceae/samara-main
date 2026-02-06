// call-audio-tap: Record audio from a specific app using ScreenCaptureKit
//
// Uses Apple's ScreenCaptureKit to tap into an app's audio output directly,
// bypassing virtual audio device routing. This works on macOS 26 where
// Loopback per-app capture of FaceTime is broken.
//
// Usage:
//   call-audio-tap --app FaceTime --output /path/to/output.wav [--duration 60]
//   call-audio-tap --list-apps

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// MARK: - Audio Writer

class WAVWriter {
    let url: URL
    var file: AVAudioFile?
    let sampleRate: Double
    let channels: UInt32
    var totalFrames: Int64 = 0

    init(url: URL, sampleRate: Double = 48000, channels: UInt32 = 2) {
        self.url = url
        self.sampleRate = sampleRate
        self.channels = channels
    }

    func write(buffer: AVAudioPCMBuffer) throws {
        if file == nil {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        try file?.write(from: buffer)
        totalFrames += Int64(buffer.frameLength)
    }

    func close() {
        file = nil
    }
}

// MARK: - Stream Handler

class AudioTapHandler: NSObject, SCStreamOutput {
    let writer: WAVWriter
    var hasReceivedAudio = false

    init(writer: WAVWriter) {
        self.writer = writer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid else { return }

        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }

        let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
        guard let blockBuffer = blockBuffer else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let dataPointer = dataPointer, length > 0 else { return }

        let channelCount = UInt32(asbd.pointee.mChannelsPerFrame)
        let sampleRate = asbd.pointee.mSampleRate
        let frameCount = UInt32(CMSampleBufferGetNumSamples(sampleBuffer))

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: channelCount == 1
        ) else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        // Copy audio data
        let bytesPerFrame = Int(asbd.pointee.mBytesPerFrame)
        if bytesPerFrame > 0 && channelCount > 0 {
            if asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
                // Non-interleaved
                let framesBytes = Int(frameCount) * MemoryLayout<Float>.size
                for ch in 0..<Int(channelCount) {
                    if let dest = buffer.floatChannelData?[ch] {
                        let src = dataPointer.advanced(by: ch * framesBytes)
                        memcpy(dest, src, framesBytes)
                    }
                }
            } else {
                // Interleaved - deinterleave
                let srcPtr = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: Int(frameCount) * Int(channelCount))
                for ch in 0..<Int(channelCount) {
                    if let dest = buffer.floatChannelData?[ch] {
                        for f in 0..<Int(frameCount) {
                            dest[f] = srcPtr[f * Int(channelCount) + ch]
                        }
                    }
                }
            }
        }

        // Check if audio has non-zero samples
        if !hasReceivedAudio {
            if let data = buffer.floatChannelData?[0] {
                for i in 0..<min(Int(frameCount), 1000) {
                    if abs(data[i]) > 0.0001 {
                        hasReceivedAudio = true
                        FileHandle.standardError.write("call-audio-tap: receiving audio data\n".data(using: .utf8)!)
                        break
                    }
                }
            }
        }

        do {
            try writer.write(buffer: buffer)
        } catch {
            FileHandle.standardError.write("call-audio-tap: write error: \(error)\n".data(using: .utf8)!)
        }
    }
}

// MARK: - Main

func printUsage() {
    let msg = """
    Usage: call-audio-tap --app <AppName> --output <path.wav> [--duration <seconds>]
           call-audio-tap --list-apps

    Options:
      --app <name>       App to record audio from (e.g., FaceTime)
      --output <path>    Output WAV file path
      --duration <secs>  Recording duration in seconds (default: 60)
      --list-apps        List running apps available for audio tapping
    """
    print(msg)
}

func listApps() async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let apps = content.applications.sorted { $0.applicationName < $1.applicationName }
        for app in apps {
            print("\(app.applicationName) (PID: \(app.processID))")
        }
    } catch {
        FileHandle.standardError.write("Error listing apps: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

func recordApp(appName: String, outputPath: String, duration: Double) async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let app = content.applications.first(where: {
            $0.applicationName.lowercased() == appName.lowercased()
        }) else {
            FileHandle.standardError.write("Error: App '\(appName)' not found. Use --list-apps to see available apps.\n".data(using: .utf8)!)
            exit(1)
        }

        FileHandle.standardError.write("call-audio-tap: tapping audio from \(app.applicationName) (PID: \(app.processID))\n".data(using: .utf8)!)

        // Use display-level filter with includingApplications to capture all
        // audio from the target app, including system-level call audio.
        guard let display = content.displays.first else {
            FileHandle.standardError.write("Error: No displays found\n".data(using: .utf8)!)
            exit(1)
        }
        let appFilter = SCContentFilter(display: display, including: [app], exceptingWindows: [])

        let config = SCStreamConfiguration()
        // Audio config
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        // Minimize video overhead (we only want audio)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum

        // Exclude self from capture
        if #available(macOS 14.2, *) {
            config.captureMicrophone = false
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        let writer = WAVWriter(url: outputURL, sampleRate: 48000, channels: 2)
        let handler = AudioTapHandler(writer: writer)

        let stream = SCStream(filter: appFilter, configuration: config, delegate: nil)
        try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio-tap"))

        try await stream.startCapture()
        FileHandle.standardError.write("call-audio-tap: recording for \(Int(duration))s...\n".data(using: .utf8)!)

        // Record for specified duration
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        try await stream.stopCapture()
        writer.close()

        let frames = writer.totalFrames
        let seconds = Double(frames) / 48000.0
        let hasAudio = handler.hasReceivedAudio

        // Output result as JSON
        let result: [String: Any] = [
            "outputFile": outputPath,
            "totalFrames": frames,
            "durationSeconds": seconds,
            "hasNonZeroAudio": hasAudio,
            "app": app.applicationName,
            "pid": app.processID
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: result),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }

    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// Parse arguments
var appName: String?
var outputPath: String?
var duration: Double = 60
var listMode = false

var args = CommandLine.arguments.dropFirst()
while let arg = args.first {
    args = args.dropFirst()
    switch arg {
    case "--app":
        appName = args.first
        args = args.dropFirst()
    case "--output":
        outputPath = args.first
        args = args.dropFirst()
    case "--duration":
        if let d = args.first, let val = Double(d) {
            duration = val
        }
        args = args.dropFirst()
    case "--list-apps":
        listMode = true
    case "--help", "-h":
        printUsage()
        exit(0)
    default:
        break
    }
}

// Run
let semaphore = DispatchSemaphore(value: 0)

Task {
    if listMode {
        await listApps()
    } else if let app = appName, let output = outputPath {
        await recordApp(appName: app, outputPath: output, duration: duration)
    } else {
        printUsage()
        exit(1)
    }
    semaphore.signal()
}

semaphore.wait()
