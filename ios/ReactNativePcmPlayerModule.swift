import ExpoModulesCore
import Foundation
import AVFoundation

public class ReactNativePcmPlayerModule: Module {
  private let player = AudioPlayer.shared

  public func definition() -> ModuleDefinition {
    Name("ReactNativePcmPlayer")

    Events("onMessage", "onStatus")

    Function("enqueuePcm") { (base64Data: String) in
      guard let pcmData = Data(base64Encoded: base64Data) else {
        print("Invalid base64 PCM data")
        return
      }

      player.enqueuePcmData(pcmData) { status in
        self.sendEvent("onStatus", ["status": status])
      }
    }

    Function("stopCurrentPcm") {
      player.stopAndRelease()
    }

    Function("markAsEnded") {
      player.markAsEnded()
    }
  }
}

class AudioPlayer {
  static let shared = AudioPlayer()

  private var audioEngine = AVAudioEngine()
  private var playerNode = AVAudioPlayerNode()
  private var isPlaying = false
  private var hasEnded = false
  private var bufferQueue: [Data] = []
  private let queue = DispatchQueue(label: "pcm-player-queue")
  private let MIN_BUFFER_BYTES = 50_000
  private var playbackTask: Task<Void, Never>?

  func enqueuePcmData(_ data: Data, onStatus: @escaping (String) -> Void) {
    queue.async {
      self.bufferQueue.append(data)

      if self.isPlaying { return }
      self.isPlaying = true

      self.playbackTask = Task.detached(priority: .background) {
        do {
          try await self.waitForBuffer(timeoutMs: 2000)
          try self.startAudio()
          try await self.writeLoop()
        } catch {
          print("Playback error: \(error)")
        }

        self.stopInternal()
        onStatus("listening")
      }
    }
  }

  func markAsEnded() {
    queue.sync {
      print("Marking as ended")
      hasEnded = true
    }
  }

  func stopAndRelease() {
    print("Stop requested from JS")
    queue.async {
      self.stopInternal()
    }
  }

  private func waitForBuffer(timeoutMs: Int) async throws {
    print("Waiting for prebuffer...")
    let start = Date()
    while getQueueSizeInBytes() < MIN_BUFFER_BYTES && !getHasEnded() {
      if Date().timeIntervalSince(start) * 1000 > Double(timeoutMs) {
        print("Prebuffer timeout, continuing anyway")
        break
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
  }

  private func startAudio() throws {
    print("Starting audio engine")
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)

    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 24000,
      channels: 1,
      interleaved: false
    )!

    audioEngine = AVAudioEngine()
    playerNode = AVAudioPlayerNode()

    audioEngine.attach(playerNode)
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

    try audioEngine.start()
    playerNode.play()
    print("Audio engine started")
  }

  private func writeLoop() async throws {
    while getIsPlaying() {
      if let data = dequeueData() {
        if let buffer = makePCMBuffer(from: data) {
          playerNode.scheduleBuffer(buffer, completionHandler: nil)
        } else {
          print("Failed to create buffer, skipping")
        }
        let frameCount = UInt32(data.count / 2)
        let duration = Double(frameCount) / 24000.0
        let sleepNs = UInt64(duration * 1_000_000_000)
        try await Task.sleep(nanoseconds: sleepNs)
      } else {
        var retries = 0
        while getQueueIsEmpty() && retries < 100 && getIsPlaying() {
          try await Task.sleep(nanoseconds: 10_000_000)
          retries += 1
        }
        if getQueueIsEmpty() {
          print("No more data, exiting playback")
          break
        }
      }
    }
  }

  private func stopInternal() {
    print("Cleaning up player")
    playbackTask?.cancel()
    playbackTask = nil
    playerNode.stop()
    audioEngine.stop()
    queue.sync {
      bufferQueue.removeAll()
      isPlaying = false
      hasEnded = false
    }
  }

  private func dequeueData() -> Data? {
    var result: Data?
    queue.sync {
      if !bufferQueue.isEmpty {
        result = bufferQueue.removeFirst()
      }
    }
    return result
  }

  private func getQueueSizeInBytes() -> Int {
    queue.sync {
      bufferQueue.reduce(0) { $0 + $1.count }
    }
  }

  private func getQueueIsEmpty() -> Bool {
    queue.sync {
      bufferQueue.isEmpty
    }
  }

  private func getIsPlaying() -> Bool {
    queue.sync { isPlaying }
  }

  private func getHasEnded() -> Bool {
    queue.sync { hasEnded }
  }

  private func makePCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
    let frameCount = UInt32(data.count / 2)
    guard let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 24000,
      channels: 1,
      interleaved: false
    ),
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
    let floatChannel = buffer.floatChannelData?[0] else {
      print("Buffer allocation failed")
      return nil
    }
    buffer.frameLength = frameCount

    data.withUnsafeBytes { rawBuffer in
      let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
      for i in 0..<Int(frameCount) {
        floatChannel[i] = Float(int16Ptr[i]) / Float(Int16.max)
      }
    }

    return buffer
  }
}
