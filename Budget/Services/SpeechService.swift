import Foundation

#if os(iOS)
import Speech
import AVFoundation

/// Wraps SFSpeechRecognizer + AVAudioEngine for live, en-US dictation.
/// Use:
///   1. `await requestAuthorization()` once on first use
///   2. `startRecording()` to begin streaming → updates `transcript`
///   3. `stopRecording()` to finalize and stop the audio engine
@Observable
@MainActor
final class SpeechService {
    var transcript: String = ""
    var isRecording: Bool = false
    var isAuthorized: Bool = false
    var error: String? = nil

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let audioEngine = AVAudioEngine()

    // MARK: - Authorization

    /// Requests both Speech and Microphone permissions. Updates `isAuthorized`.
    /// Safe to call repeatedly.
    func requestAuthorization() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            self.isAuthorized = false
            self.error = "Speech recognition not authorized. Enable in Settings → Budget."
            return
        }

        let micGranted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            self.isAuthorized = false
            self.error = "Microphone access denied. Enable in Settings → Budget."
            return
        }

        self.isAuthorized = true
        self.error = nil
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            self.error = "Speech recognizer unavailable."
            return
        }

        // Cancel any prior task.
        recognitionTask?.cancel()
        recognitionTask = nil

        do {
            // Configure audio session for record + measurement (low-latency, no echo cancel).
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Try on-device if available — keeps the audio off the network for privacy.
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            transcript = ""
            error = nil

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, err in
                Task { @MainActor in
                    if let result {
                        self?.transcript = result.bestTranscription.formattedString
                    }
                    if let err {
                        self?.error = err.localizedDescription
                        self?.stopRecording()
                    }
                }
            }
        } catch {
            self.error = "Couldn't start recording: \(error.localizedDescription)"
            cleanup()
        }
    }

    /// Stops audio capture but lets the recognizer finalize the last buffer.
    /// Returns the final transcript snapshot (also available on `transcript`).
    @discardableResult
    func stopRecording() -> String {
        guard isRecording else { return transcript }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        // Defer task cancellation slightly so the final partial result lands.
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return transcript
    }

    private func cleanup() {
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}

#endif
