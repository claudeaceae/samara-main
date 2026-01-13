import AVFoundation
import AppKit

/// Captures photos from the webcam using AVFoundation
/// This runs within Samara.app's process, using Samara's camera permission
protocol CameraCapturing {
    func capture(to path: String) async throws -> String
}

final class CameraCapture: NSObject, CameraCapturing {
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var continuation: CheckedContinuation<String, Error>?
    private var outputPath: String?

    /// Errors that can occur during capture
    enum CaptureError: Error, LocalizedError {
        case noCamera
        case setupFailed(String)
        case captureFailed(String)
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .noCamera:
                return "No camera device found"
            case .setupFailed(let reason):
                return "Camera setup failed: \(reason)"
            case .captureFailed(let reason):
                return "Photo capture failed: \(reason)"
            case .accessDenied:
                return "Camera access denied"
            }
        }
    }

    /// Capture a photo to the specified path
    /// - Parameter path: Where to save the captured image (JPEG format)
    /// - Returns: The path to the saved image
    func capture(to path: String) async throws -> String {
        // Check camera authorization
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw CaptureError.accessDenied
            }
        case .denied, .restricted:
            throw CaptureError.accessDenied
        case .authorized:
            break
        @unknown default:
            break
        }

        // Find the Logitech C920 or any available camera
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )

        // Prefer external camera (Logitech), fall back to built-in
        let device = discoverySession.devices.first { $0.localizedName.contains("C920") }
            ?? discoverySession.devices.first

        guard let camera = device else {
            throw CaptureError.noCamera
        }

        log("Using camera: \(camera.localizedName)", level: .info, component: "CameraCapture")

        // Set up capture session
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                throw CaptureError.setupFailed("Cannot add camera input")
            }
        } catch {
            throw CaptureError.setupFailed(error.localizedDescription)
        }

        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            throw CaptureError.setupFailed("Cannot add photo output")
        }

        self.captureSession = session
        self.photoOutput = output
        self.outputPath = path

        // Start the session
        session.startRunning()

        // Wait for camera to warm up (adjust exposure)
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

        // Capture the photo
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off

            output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Clean up resources
    private func cleanup() {
        captureSession?.stopRunning()
        captureSession = nil
        photoOutput = nil
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraCapture: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { cleanup() }

        if let error = error {
            continuation?.resume(throwing: CaptureError.captureFailed(error.localizedDescription))
            continuation = nil
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            continuation?.resume(throwing: CaptureError.captureFailed("No image data"))
            continuation = nil
            return
        }

        guard let outputPath = outputPath else {
            continuation?.resume(throwing: CaptureError.captureFailed("No output path"))
            continuation = nil
            return
        }

        // Convert to JPEG and save
        guard let image = NSImage(data: imageData),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            continuation?.resume(throwing: CaptureError.captureFailed("Failed to convert to JPEG"))
            continuation = nil
            return
        }

        do {
            try jpegData.write(to: URL(fileURLWithPath: outputPath))
            log("Photo saved to: \(outputPath)", level: .info, component: "CameraCapture")
            continuation?.resume(returning: outputPath)
        } catch {
            continuation?.resume(throwing: CaptureError.captureFailed("Failed to save: \(error.localizedDescription)"))
        }
        continuation = nil
    }
}

// MARK: - Capture Request Watcher

/// Watches for capture requests from Claude and triggers camera capture
final class CaptureRequestWatcher {
    private let requestPath: String
    private let resultPath: String
    private let camera: CameraCapturing
    private let pollInterval: DispatchTimeInterval
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "samara.capture-watcher", qos: .userInitiated)

    init(
        statePath: String = MindPaths.mindPath("state"),
        camera: CameraCapturing = CameraCapture(),
        pollInterval: DispatchTimeInterval = .milliseconds(500)
    ) {
        self.requestPath = (statePath as NSString).appendingPathComponent("capture-request.json")
        self.resultPath = (statePath as NSString).appendingPathComponent("capture-result.json")
        self.camera = camera
        self.pollInterval = pollInterval

        // Ensure state directory exists
        try? FileManager.default.createDirectory(atPath: statePath, withIntermediateDirectories: true)
    }

    /// Start watching for capture requests
    func start() {
        log("CaptureRequestWatcher started", level: .info, component: "CameraCapture")

        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: pollInterval)
        timer?.setEventHandler { [weak self] in
            self?.checkForRequest()
        }
        timer?.resume()
    }

    /// Stop watching
    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func checkForRequest() {
        guard FileManager.default.fileExists(atPath: requestPath) else {
            return
        }

        // Read and delete request atomically
        guard let data = FileManager.default.contents(atPath: requestPath),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outputPath = request["output"] as? String else {
            // Invalid request, delete it
            try? FileManager.default.removeItem(atPath: requestPath)
            return
        }

        // Delete request file immediately to prevent re-processing
        try? FileManager.default.removeItem(atPath: requestPath)

        log("Capture request received: \(outputPath)", level: .info, component: "CameraCapture")

        // Process capture on main thread (AVFoundation requirement)
        Task { @MainActor in
            await self.processCapture(outputPath: outputPath)
        }
    }

    @MainActor
    private func processCapture(outputPath: String) async {
        var result: [String: Any] = [:]

        do {
            let path = try await camera.capture(to: outputPath)
            result["success"] = true
            result["path"] = path
            log("Capture successful: \(path)", level: .info, component: "CameraCapture")
        } catch {
            result["success"] = false
            result["error"] = error.localizedDescription
            log("Capture failed: \(error)", level: .error, component: "CameraCapture")
        }

        result["timestamp"] = ISO8601DateFormatter().string(from: Date())

        // Write result
        if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted) {
            try? jsonData.write(to: URL(fileURLWithPath: resultPath))
        }
    }
}
