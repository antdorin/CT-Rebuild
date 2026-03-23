import Foundation
import Speech
import AVFoundation

// MARK: - SpeechManager
// Fixes vs previous attempts:
//  1. AVAudioSession configured BEFORE accessing inputNode (prevents sampleRate=0 crash)
//  2. inputFormat(forBus:0) — NOT outputFormat
//  3. sampleRate > 0 guard before installTap
//  4. Tap removed before reinstall (no duplicate-tap crash)
//  5. endAudio() + cancel() both called on stop so callbacks cease immediately

@MainActor
final class SpeechManager: ObservableObject {
    @Published var isRecording      = false
    @Published var partial: String  = ""
    @Published var permissionDenied = false

    private(set) var baseText: String = ""

    private let recognizer   = SFSpeechRecognizer(locale: .init(identifier: "en-US"))
    private var request:     SFSpeechAudioBufferRecognitionRequest?
    private var task:        SFSpeechRecognitionTask?
    private let engine       = AVAudioEngine()
    private var tapInstalled = false

    // MARK: Public

    func start(baseText: String) {
        guard !isRecording else { return }
        self.baseText = baseText
        self.partial  = ""

        Task { @MainActor in
            let speechStatus: SFSpeechRecognizerAuthorizationStatus =
                await withCheckedContinuation { cont in
                    SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
                }
            guard speechStatus == .authorized else { permissionDenied = true; return }

            let micGranted: Bool =
                await withCheckedContinuation { cont in
                    AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
                }
            guard micGranted else { permissionDenied = true; return }

            startEngine()
        }
    }

    func stop() {
        guard isRecording || tapInstalled else { return }
        isRecording = false
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task    = nil
        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    // MARK: Private

    private func startEngine() {
        do {
            // 1. Configure session FIRST — this is what populates inputNode's format
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // 2. Build recognition request
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            self.request = req

            // 3. inputFormat (NOT outputFormat), validated after session is active
            let inputNode = engine.inputNode
            let fmt = inputNode.inputFormat(forBus: 0)
            guard fmt.sampleRate > 0 else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }

            // 4. Remove stale tap if present, then install fresh
            if tapInstalled { inputNode.removeTap(onBus: 0); tapInstalled = false }
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak req] buf, _ in
                req?.append(buf)
            }
            tapInstalled = true

            // 5. Recognition task
            task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor [weak self] in
                        self?.partial = result.bestTranscription.formattedString
                    }
                }
                if error != nil || result?.isFinal == true {
                    Task { @MainActor [weak self] in self?.stop() }
                }
            }

            // 6. Start engine
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            stop()
        }
    }
}
