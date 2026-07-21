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

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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
            cleanup()
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        cleanup()
        isRecording = false
    }

    func reset() {
        stop()
        transcript = ""
        errorText = nil
    }

    private func cleanup() {
        request = nil
        task = nil
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
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        guard let recognizer, recognizer.isAvailable else {
            throw NSError(
                domain: "SpeechCapture", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable."]
            )
        }

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
