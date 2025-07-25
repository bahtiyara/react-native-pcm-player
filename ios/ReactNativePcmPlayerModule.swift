import ExpoModulesCore
import AVFoundation
import os.lock

public class ReactNativePcmPlayerModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ReactNativePcmPlayer")

    Events("onMessage", "onStatus")

    Function("enqueuePcm") { (base64Data: String) in
      Task {
        await CurrentAudioPlayer.shared.enqueuePcmData(base64Data) { status in
          self.sendEvent("onStatus", [
            "status": status
          ])
        }
      }
    }

    Function("stopCurrentPcm") {
      Task {
        await CurrentAudioPlayer.shared.stopAndRelease()
      }
    }

    Function("markAsEnded") {
      Task {
        await CurrentAudioPlayer.shared.markAsEnded()
      }
    }
  }
}

@objc class CurrentAudioPlayer: NSObject {
  actor State {
    var audioEngine: AVAudioEngine?
    var audioPlayerNode: AVAudioPlayerNode?
    var bufferQueue: [Data] = []
    var isPlaying = false
    var hasEnded = false
    var scheduledBufferCount = 0
    
    func appendData(_ data: Data) {
      bufferQueue.append(data)
    }
    
    func setHasEnded(_ hasEnded: Bool) {
      self.hasEnded = hasEnded
    }
    
    func setIsPlaying(_ isPlaying: Bool) {
      self.isPlaying = isPlaying
    }
    
    func setEngine(_ engine: AVAudioEngine?) {
      audioEngine = engine
    }
    
    func setPlayerNode(_ node: AVAudioPlayerNode?) {
      audioPlayerNode = node
    }
    
    func dequeueFirstData() -> Data? {
      guard !bufferQueue.isEmpty else {
        return nil
      }
      return bufferQueue.removeFirst()
    }
    
    func increseScheduledBufferCount() {
      scheduledBufferCount += 1
    }
    
    func decreaseScheduledBufferCount() {
      scheduledBufferCount -= 1
    }
    
    func reset() {
      audioEngine = nil
      audioPlayerNode = nil
      bufferQueue.removeAll()
      isPlaying = false
      hasEnded = false
    }
  }
  
  static let shared = CurrentAudioPlayer()
  
  private let state = State()
  private let minBufferBytes = 50_000

  func enqueuePcmData(_ b64Str: String, onStatus: @escaping (String) -> Void) async {
    guard let data = Data(base64Encoded: b64Str) else {
      return
    }
    
    await self.state.appendData(data)
    await self.state.setHasEnded(false)
    
    if await !self.state.isPlaying {
      await self.state.setIsPlaying(true)
      
      print(">>> Starting new playback")
      
      await self.waitForBuffer()
      await self.startAudioEngine()
      self.writeLoop(onStatus: onStatus)
    }
  }
  
  func scheduleBufferAsync(playerNode: AVAudioPlayerNode, buffer: AVAudioPCMBuffer) async {
      await withCheckedContinuation { continuation in
          playerNode.scheduleBuffer(buffer) {
              // This block runs when the buffer finishes playing
              continuation.resume()
          }
      }
  }

  func markAsEnded() async {
    print(">>> Marking as ended")
    await self.state.setHasEnded(true)
  }

  func stopAndRelease() async {
    print(">>> Stop requested")
    await self.stopInternal()
  }

  private func waitForBuffer() async {
    print(">>> Waiting for prebuffer...")
    var hasEnded = await state.hasEnded
    var isSmallSize = await getQueueSizeInBytes() < minBufferBytes
    
    while !hasEnded && isSmallSize {
      try? await Task.sleep(nanoseconds: 10_000_000)
      hasEnded = await state.hasEnded
      isSmallSize = await getQueueSizeInBytes() < minBufferBytes
    }
  }

  private func startAudioEngine() async {
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
      await state.setEngine(engine)
      await state.setPlayerNode(playerNode)
      print(">>> AudioEngine started")
    } catch {
      print(">>> Error starting audio engine: \(error)")
    }
  }

  private func writeLoop(onStatus: @escaping (String) -> Void) {
    Task.detached {
      while await self.state.isPlaying {
        guard let data = await self.state.dequeueFirstData() else {
          for _ in 0..<1000 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            let isBufferEmpty = await self.state.bufferQueue.isEmpty
            let hasEnded = await self.state.hasEnded
            if !isBufferEmpty || hasEnded {
              break
            }
          }
          if await self.state.bufferQueue.isEmpty {
            print(">>> No more data, exiting playback")
            break
          }
          continue
        }
        
        if let buffer = await self.pcmBuffer(from:data), let node = await self.state.audioPlayerNode {
          await self.state.increseScheduledBufferCount()
          await self.scheduleBufferAsync(playerNode: node, buffer: buffer)
          await self.state.decreaseScheduledBufferCount()
          let isBufferEmpty = await self.state.bufferQueue.isEmpty
          let isScheduledBufferEmpty = await self.state.scheduledBufferCount == 0
          let isEnded = await self.state.hasEnded
        
          if isBufferEmpty && isEnded && isScheduledBufferEmpty {
              print(">>> Playback fully completed")
              onStatus("listening")
              await self.stopInternal()
          }
        }
      }
    }
  }

  /** 
   * This function is to convert 16 bit audio format into 32 bit
   */
  private func pcmBuffer(from data: Data) async -> AVAudioPCMBuffer? {
    let frameCount = UInt32(data.count) / 2
    guard let format = await state.audioPlayerNode?.outputFormat(forBus: 0),
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

  private func stopInternal() async {
    print(">>> Cleaning up player")
    let node = await state.audioPlayerNode
    let engine = await state.audioEngine
    node?.stop()
    engine?.stop()
    engine?.reset()
    await state.reset()
  }

  private func getQueueSizeInBytes() async -> Int {
    await state.bufferQueue.reduce(0) { $0 + $1.count }
  }
}
