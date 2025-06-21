import AVFoundation

@objc class CurrentAudioPlayer: NSObject {
  static let shared = CurrentAudioPlayer()

  private var audioEngine: AVAudioEngine?
  private var audioPlayerNode: AVAudioPlayerNode?
  private let pcmQueue = DispatchQueue(label: "pcm.queue", qos: .userInitiated)
  private var bufferQueue = [Data]()
  private var isPlaying = false
  private var hasEnded = false
  private let minBufferBytes = 50_000

  func enqueuePcmData(_ data: Data, onStatus: @escaping (String) -> Void) {
    pcmQueue.async {
      self.bufferQueue.append(data)

      if !self.isPlaying {
        self.isPlaying = true
        self.hasEnded = false
        print("Starting new playback")
        Task {
          await self.waitForBuffer()
          self.startAudioEngine()
          self.writeLoop(onStatus: onStatus)
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
    print("Stop requested")
    pcmQueue.async {
      self.stopInternal()
    }
  }

  private func waitForBuffer() async {
    print("Waiting for prebuffer...")
    while getQueueSizeInBytes() < minBufferBytes && !hasEnded {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  private func startAudioEngine() {
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    engine.attach(playerNode)

    let format = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
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
      print("AudioEngine started")
    } catch {
      print("Error starting audio engine: \(error)")
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
            print("No more data, exiting playback")
            break
          }
        }

        let data = self.bufferQueue.removeFirst()
        if let buffer = self.pcmBuffer(from: data) {
          self.audioPlayerNode?.scheduleBuffer(buffer, completionHandler: nil)
        }
      }

      self.stopInternal()
      onStatus("listening")
    }
  }

  private func pcmBuffer(from data: Data) -> AVAudioPCMBuffer? {
    let frameCount = UInt32(data.count) / 2
    guard let format = audioPlayerNode?.outputFormat(forBus: 0),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
      return nil
    }

    buffer.frameLength = frameCount
    let channels = buffer.int16ChannelData!
    data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
      let src = ptr.bindMemory(to: Int16.self)
      channels[0].assign(from: src.baseAddress!, count: Int(frameCount))
    }

    return buffer
  }

  private func stopInternal() {
    print("Cleaning up player")
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
