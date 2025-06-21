package expo.modules.pcmplayer

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

    fun enqueuePcmData(data: ByteArray, onStatus: (String) -> Unit) {
        pcmQueue.offer(data)

        if (isPlaying.compareAndSet(false, true)) {
            println("Starting new playback job")
            playbackJob = scope.launch {
                try {
                    waitForBuffer()
                    startAudioTrack()
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

    private fun startAudioTrack() {
        val sampleRate = 24000
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
            } else {
                var retries = 0
                while (pcmQueue.isEmpty() && retries < 100) {
                    delay(10)
                    retries++
                }
                if (pcmQueue.isEmpty()) {
                    println("No more data, exiting playback")
                    break
                }
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