package expo.modules.opuslib

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

/**
 * OpuslibModule - Expo module for Opus 1.6 audio encoding with DRED support
 *
 * This module provides native audio capture and Opus 1.6 encoding with Deep Redundancy (DRED)
 * for improved audio quality on lossy networks.
 */
class OpuslibModule : Module() {
  private var audioRecordManager: AudioRecordManager? = null
  private var isStreaming = false

  override fun definition() = ModuleDefinition {
    Name("Opuslib")

    // Events
    Events("audioChunk", "amplitude", "audioStarted", "audioEnd", "error")

    // Start streaming method
    AsyncFunction("startStreaming") { config: AudioConfig ->
      startStreaming(config)
    }

    // Stop streaming method
    AsyncFunction("stopStreaming") {
      stopStreaming()
    }

    // Pause streaming method
    Function("pauseStreaming") {
      pauseStreaming()
    }

    // Resume streaming method
    Function("resumeStreaming") {
      resumeStreaming()
    }
  }

  // MARK: - Public Methods

  private fun startStreaming(config: AudioConfig) {
    android.util.Log.d(TAG, "🎬 startStreaming() called with DRED: ${config.dredDuration}ms")

    if (isStreaming) {
      throw AudioStreamException("ALREADY_STREAMING", "Audio streaming is already active")
    }

    // Check microphone permission
    val context = appContext.reactContext ?: throw AudioStreamException(
      "NO_CONTEXT",
      "React context not available"
    )

    if (ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.RECORD_AUDIO
      ) != PackageManager.PERMISSION_GRANTED
    ) {
      throw AudioStreamException(
        "PERMISSION_DENIED",
        "Microphone permission not granted"
      )
    }

    android.util.Log.d(TAG, "✅ Microphone permission granted")

    // Create audio record manager
    android.util.Log.d(TAG, "🏗️ Creating AudioRecordManager...")
    val manager = AudioRecordManager(context, config)
    android.util.Log.d(TAG, "✅ AudioRecordManager created")

    // Set up event callbacks — audioStarted/audioEnd come from encoding thread
    android.util.Log.d(TAG, "🔗 Setting up event callbacks...")
    manager.setOnAudioChunk { data, timestamp, sequenceNumber, audioLevel, duration, frameCount ->
      sendEvent("audioChunk", mapOf(
        "data" to data,
        "timestamp" to timestamp,
        "sequenceNumber" to sequenceNumber,
        "audioLevel" to audioLevel,
        "duration" to duration,
        "frameCount" to frameCount
      ))
    }

    manager.setOnStarted { timestamp, sampleRate, channels, bitrate, frameSize, preSkip ->
      sendEvent("audioStarted", mapOf(
        "timestamp" to timestamp,
        "sampleRate" to sampleRate,
        "channels" to channels,
        "bitrate" to bitrate,
        "frameSize" to frameSize,
        "preSkip" to preSkip
      ))
    }

    manager.setOnEnd { timestamp, totalDuration, totalPackets ->
      sendEvent("audioEnd", mapOf(
        "timestamp" to timestamp,
        "totalDuration" to totalDuration,
        "totalPackets" to totalPackets
      ))
    }

    manager.setOnAmplitude { rms, peak, timestamp ->
      sendEvent("amplitude", mapOf(
        "rms" to rms,
        "peak" to peak,
        "timestamp" to timestamp
      ))
    }

    manager.setOnError { error ->
      android.util.Log.e(TAG, "❌ Error from manager: ${error.message}")
      sendEvent("error", mapOf(
        "code" to "AUDIO_RECORD_ERROR",
        "message" to error.message
      ))
    }

    // Start audio capture + encoding
    android.util.Log.d(TAG, "🚀 Calling manager.start()...")
    manager.start()
    android.util.Log.d(TAG, "✅ manager.start() completed")

    audioRecordManager = manager
    isStreaming = true

    android.util.Log.d(TAG, "✅ Started streaming")
  }

  private fun stopStreaming() {
    if (!isStreaming) {
      return
    }

    // stop() triggers flushAndStop() which emits audioEnd from encoding thread
    audioRecordManager?.stop()
    audioRecordManager = null
    isStreaming = false

    android.util.Log.d(TAG, "Stopped streaming")
  }

  private fun pauseStreaming() {
    if (!isStreaming) {
      return
    }

    audioRecordManager?.pause()
    android.util.Log.d(TAG, "Paused streaming")
  }

  private fun resumeStreaming() {
    if (!isStreaming) {
      return
    }

    audioRecordManager?.resume()
    android.util.Log.d(TAG, "Resumed streaming")
  }

  companion object {
    private const val TAG = "OpuslibModule"
  }
}

// MARK: - Configuration

/**
 * Audio configuration for Opus encoding
 */
class AudioConfig : Record {
  @Field
  var sampleRate: Int = 16000

  @Field
  var channels: Int = 1

  @Field
  var bitrate: Int = 24000

  @Field
  var frameSize: Double = 20.0

  @Field
  var packetDuration: Double = 20.0

  @Field
  var dredDuration: Int = 100  // NEW: DRED recovery duration in ms

  @Field
  var enableAmplitudeEvents: Boolean = false

  @Field
  var amplitudeEventInterval: Double = 16.0

  @Field
  var audioLevelWindow: Int = 360  // RMS window duration in ms (default 360)

  @Field
  var saveDebugAudio: Boolean = false
}

// MARK: - Errors

/**
 * Custom exception for audio streaming errors
 */
class AudioStreamException(code: String, message: String) : CodedException(code, message, null)
