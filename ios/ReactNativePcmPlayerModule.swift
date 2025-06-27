import ExpoModulesCore

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

