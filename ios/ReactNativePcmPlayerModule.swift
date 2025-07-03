import ExpoModulesCore
import AVFoundation

public class ReactNativePcmPlayerModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ReactNativePcmPlayer")

    Events("onMessage", "onStatus")

    Function("enqueuePcm") { (base64Data: String) in
      if let data = Data(base64Encoded: base64Data) {
        CurrentAudioPlayer.shared.enqueuePcmData(data) { status in
          self.sendEvent("onStatus", [
            "status": status
          ])
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

@objc class CurrentAudioPlayer: NSObject {
  static let shared = CurrentAudioPlayer()

  private var audioEngine: AVAudioEngine?
  private var audioPlayerNode: AVAudioPlayerNode?
  private let pcmQueue = DispatchQueue(label: "pcm.queue", qos: .userInitiated)
  private var bufferQueue = [Data]()
  private var isPlaying = false
  private var hasEnded = false
  private let minBufferBytes = 50_000
  private var scheduledBufferCount = 0

  func enqueuePcmData(_ data: Data, onStatus: @escaping (String) -> Void) {
    pcmQueue.async {
      self.bufferQueue.append(data)

      if !self.isPlaying {
        self.isPlaying = true
        
        print(">>> Starting new playback")
        Task {
          await self.waitForBuffer()
          self.startAudioEngine()
          self.writeLoop(onStatus: onStatus)
        }
      }
    }
  }

  func markAsEnded() {
    print(">>> Marking as ended")
    pcmQueue.async {
      self.hasEnded = true
    }
  }

  func stopAndRelease() {
    print(">>> Stop requested")
    pcmQueue.async {
      self.stopInternal()
    }
  }

  private func waitForBuffer() async {
    print(">>> Waiting for prebuffer...")
    while getQueueSizeInBytes() < minBufferBytes && !hasEnded {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  private func startAudioEngine() {
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    engine.attach(playerNode)

    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 24000,
      channels: 1,
      interleaved: true
    )!

    engine.connect(playerNode, to: engine.mainMixerNode, format: format)

    do {
      try engine.start()
      playerNode.play()
      self.audioEngine = engine
      self.audioPlayerNode = playerNode
      print(">>> AudioEngine started")
    } catch {
      print(">>> Error starting audio engine: \(error)")
    }
  }

  private func writeLoop(onStatus: @escaping (String) -> Void) {
    Task.detached {
      while self.isPlaying {
        guard !self.bufferQueue.isEmpty else {
          for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            if !self.bufferQueue.isEmpty { break }
          }
          if self.bufferQueue.isEmpty {
            print(">>> No more data, exiting playback")
            break
          }
          continue
        }

        let data = self.bufferQueue.removeFirst()
        if let buffer = self.pcmBuffer(from: data) {
          self.scheduledBufferCount += 1
          self.audioPlayerNode?.scheduleBuffer(buffer, completionHandler: {
            self.pcmQueue.async {
                self.scheduledBufferCount -= 1
                if self.bufferQueue.isEmpty && self.scheduledBufferCount == 0 {
                    print(">>> Playback fully completed")
                    onStatus("listening")
                    self.stopInternal()
                }
            }
          })
        }
      }
    }
  }

  /** 
   * This function is to convert 16 bit audio format into 32 bit
   */
  private func pcmBuffer(from data: Data) -> AVAudioPCMBuffer? {
    let frameCount = UInt32(data.count) / 2
    guard let format = audioPlayerNode?.outputFormat(forBus: 0),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        return nil
    }

    buffer.frameLength = frameCount
    let channels = buffer.floatChannelData![0]

    data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
        let src = ptr.bindMemory(to: Int16.self)
        for i in 0..<Int(frameCount) {
            channels[i] = Float(src[i]) / Float(Int16.max)
        }
    }

    return buffer
  }

  private func stopInternal() {
    print(">>> Cleaning up player")
    audioPlayerNode?.stop()
    audioEngine?.stop()
    audioEngine?.reset()

    audioPlayerNode = nil
    audioEngine = nil
    bufferQueue.removeAll()
    isPlaying = false
    hasEnded = false
  }

  private func getQueueSizeInBytes() -> Int {
    return bufferQueue.reduce(0) { $0 + $1.count }
  }
}
