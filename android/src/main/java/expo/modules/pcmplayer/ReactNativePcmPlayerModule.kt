package expo.modules.pcmplayer

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import android.util.Base64

class PcmPlayerModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("PcmPlayerModule")

        Events("onMessage")
        Events("onStatus")

        Function("enqueuePcm") { base64Data: String ->
            val pcmData = Base64.decode(base64Data, Base64.DEFAULT)
            CurrentAudioPlayer.enqueuePcmData(pcmData) { status ->
                sendEvent("onStatus", mapOf("status" to status))
            }
        }

        Function("stopCurrentPcm") {
            CurrentAudioPlayer.stopAndRelease()
        }

        Function("markAsEnded") {
            CurrentAudioPlayer.markAsEnded()
        }
    }
}

