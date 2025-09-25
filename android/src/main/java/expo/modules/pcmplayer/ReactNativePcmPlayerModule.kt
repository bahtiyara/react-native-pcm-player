package expo.modules.pcmplayer

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import android.util.Base64

import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

object CurrentAudioPlayer {
    private var audioTrack: AudioTrack? = null
    private val pcmQueue = ConcurrentLinkedQueue<ByteArray>()
    private val isPlaying = AtomicBoolean(false)
    private val hasEnded = AtomicBoolean(false)
    private var playbackJob: Job? = null
    private const val MIN_BUFFER_BYTES = 50_000
    private val scope = CoroutineScope(Dispatchers.IO)

    fun enqueuePcmData(data: ByteArray, sampleRate: Int, onStatus: (String) -> Unit) {
        pcmQueue.offer(data)

        if (isPlaying.compareAndSet(false, true)) {
            println("Starting new playback job")
            playbackJob = scope.launch {
                try {
                    waitForBuffer()
                    startAudioTrack(sampleRate)
                    writeLoop()
                } catch (e: Exception) {
                    println("Playback error: ${e.message}")
                } finally {
                    stopInternal()
                    onStatus("listening")
                }
            }
        }
    }

    fun markAsEnded() {
        println("Marking as ended")
        hasEnded.set(true)
    }

    fun stopAndRelease() {
        println("Stop requested from JS")
        scope.launch {
            stopInternal()
        }
    }

    private suspend fun waitForBuffer() {
        println("Waiting for prebuffer...")
        while (getQueueSizeInBytes() < MIN_BUFFER_BYTES  && !hasEnded.get()) {
            delay(10)
        }
    }

    private fun startAudioTrack(sampleRate: Int) {
        val minBufSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioTrack = AudioTrack(
            AudioManager.STREAM_MUSIC,
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBufSize,
            AudioTrack.MODE_STREAM
        )
        println("AudioTrack created, playing")
        audioTrack?.play()
    }

    private suspend fun writeLoop() {
        while (isPlaying.get()) {
            val data = pcmQueue.poll()
            if (data != null) {
                val result = audioTrack?.write(data, 0, data.size)
                if (result == null || result < 0) {
                    throw Exception("AudioTrack write failed: $result")
                }
                continue
            }

            repeat(100) {
                if (pcmQueue.isNotEmpty()) return@repeat
                delay(10)
            }

            if (pcmQueue.isEmpty()) {
                println("No more data, exiting playback")
                break
            }
        }
    }

    private fun stopInternal() {
        println("Cleaning up player")
        try {
            audioTrack?.apply {
                if (playState == AudioTrack.PLAYSTATE_PLAYING) stop()
                release()
            }
        } catch (e: Exception) {
            println("Error while releasing AudioTrack: ${e.message}")
        }
        audioTrack = null
        pcmQueue.clear()
        playbackJob?.cancel()
        playbackJob = null
        isPlaying.set(false)
        hasEnded.set(false)
    }

    private fun getQueueSizeInBytes(): Int {
        return pcmQueue.sumOf { it.size }
    }
}

class ReactNativePcmPlayerModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("ReactNativePcmPlayer")

        Events("onMessage")
        Events("onStatus")

        Function("enqueuePcm") { base64Data: String, sampleRate: Int = 24000 ->
            val pcmData = Base64.decode(base64Data, Base64.DEFAULT)
            CurrentAudioPlayer.enqueuePcmData(pcmData, sampleRate) { status ->
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