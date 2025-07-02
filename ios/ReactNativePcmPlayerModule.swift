import ExpoModulesCore
import AVFoundation

public class ReactNativePcmPlayerModule: Module {
    public func definition() -> ModuleDefinition {
        Name("ReactNativePcmPlayer")

        Events("onMessage", "onStatus")

        Function("enqueuePcm") { (base64Data: String) in
            if let data = Data(base64Encoded: base64Data) {
                CurrentAudioPlayer.shared.enqueuePcmData(data) { status in
                    self.sendEvent("onStatus", ["status": status])
                }
            }
        }

        Function("stopCurrentPcm") {
            CurrentAudioPlayer.shared.stopAndRelease()
        }

        Function("markAsEnded") {
            CurrentAudioPlayer.shared.markAsEnded()
        }
    }
}

class CurrentAudioPlayer {
    static let shared = CurrentAudioPlayer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let pcmQueue = DispatchQueue(label: "pcmQueue")
    private var bufferQueue = [Data]()
    private var isPlaying = false
    private var hasEnded = false
    private let minBufferBytes = 50_000

    private init() {}

    func enqueuePcmData(_ data: Data, onStatus: @escaping (String) -> Void) {
        pcmQueue.async {
            self.bufferQueue.append(data)

            if !self.isPlaying {
                self.isPlaying = true
                print("Starting new playback")
                Task {
                    do {
                        try await self.waitForBuffer()
                        try await self.startAudioEngine()
                        await self.writeLoop()
                    } catch {
                        print("Playback error: \(error.localizedDescription)")
                    }
                    self.stopInternal()
                    onStatus("listening")
                }
            }
        }
    }

    func markAsEnded() {
        print("Marking as ended")
        pcmQueue.async {
            self.hasEnded = true
        }
    }

    func stopAndRelease() {
        print("Stop requested from JS")
        pcmQueue.async {
            self.stopInternal()
        }
    }

    private func waitForBuffer() async throws {
        print("Waiting for prebuffer...")
        while getQueueSizeInBytes() < minBufferBytes && !hasEnded {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func startAudioEngine() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        try engine.start()
        playerNode.play()
        print("AudioEngine started and playing")
    }

    private func writeLoop() async {
        while isPlaying {
            var dataChunk: Data?

            pcmQueue.sync {
                if !self.bufferQueue.isEmpty {
                    dataChunk = self.bufferQueue.removeFirst()
                }
            }

            if let dataChunk = dataChunk {
                let frameLength = UInt32(dataChunk.count) / 2
                let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
                guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameLength) else {
                    print("Failed to create AVAudioPCMBuffer")
                    continue
                }
                buffer.frameLength = frameLength
                dataChunk.withUnsafeBytes { ptr in
                    if let baseAddr = ptr.baseAddress {
                        memcpy(buffer.int16ChannelData![0], baseAddr, Int(buffer.frameLength) * 2)
                    }
                }
                playerNode.scheduleBuffer(buffer, completionHandler: nil)
                continue
            }

            for _ in 0..<100 {
                if getQueueSizeInBytes() > 0 { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }

            if getQueueSizeInBytes() == 0 {
                print("No more data, exiting playback")
                break
            }
        }
    }

    private func stopInternal() {
        print("Cleaning up player")
        playerNode.stop()
        engine.stop()
        engine.reset()
        pcmQueue.sync {
            bufferQueue.removeAll()
        }
        isPlaying = false
        hasEnded = false
    }

    private func getQueueSizeInBytes() -> Int {
        pcmQueue.sync {
            return bufferQueue.reduce(0) { $0 + $1.count }
        }
    }
}
