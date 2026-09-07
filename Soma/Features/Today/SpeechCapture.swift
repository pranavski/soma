import Foundation
import AVFoundation
import Speech

/// Live-dictation wrapper around `SFSpeechRecognizer` + `AVAudioEngine`.
///
/// The capture sheet binds to `transcript` for the running text and calls
/// `start()` / `stop()` from the speak button. Failure is non-fatal — if
/// the user denies mic/speech, the typed-input path still works.
@MainActor
final class SpeechCapture: ObservableObject {
    @Published private(set) var transcript: String = ""
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var errorText: String?

    /// The person's own language first. `SFSpeechRecognizer(locale:)` is nil
    /// for a locale Apple's recogniser doesn't support, so fall back to
    /// English (US) rather than to no dictation at all — the rest of the
    /// app already follows the device locale for dates and clocks, and a
    /// hard-coded en-US gave non-English speakers poor transcripts with no
    /// hint why.
    private let recognizer = SFSpeechRecognizer(locale: .current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !isRecording else { return }
        errorText = nil

        guard await requestAuth() else { return }

        do {
            try beginSession()
            isRecording = true
        } catch {
            errorText = error.localizedDescription
            teardown()
        }
    }

    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        task?.finish()
        teardown()
        isRecording = false
    }

    func reset() {
        stop()
        transcript = ""
        errorText = nil
    }

    /// Unconditionally tears the audio graph down. `stop()` is guarded on
    /// `isRecording`, so a failure *during* `beginSession` — after the engine
    /// is running but before we flip the flag — used to leave the tap
    /// installed and the mic live, with the orange recording indicator stuck
    /// on until the app was killed. Everything here is safe to call twice.
    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        // Hand the audio session back so other apps' audio resumes.
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestAuth() async -> Bool {
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else {
            errorText = "Speech recognition isn't allowed. You can still type."
            return false
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else {
            errorText = "Microphone access is off. You can still type."
            return false
        }
        return true
    }

    private func beginSession() throws {
        // Check the recognizer *before* touching the audio hardware — the
        // old order started the engine first and then bailed, which is how
        // the mic got stranded.
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(
                domain: "SpeechCapture", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable."]
            )
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // NSSpeechRecognitionUsageDescription promises on-device recognition,
        // so honour it wherever the device can. Without this iOS is free to
        // ship the audio to Apple's servers and the purpose string becomes a
        // false privacy claim (App Review reads these).
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }
}

private extension AVAudioApplication {
    static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }
}
