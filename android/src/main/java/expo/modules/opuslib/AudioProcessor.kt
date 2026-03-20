package expo.modules.opuslib

import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch

/**
 * AudioProcessor - Dedicated encoding thread for Opus encoding and dispatch.
 *
 * Architecture (matches genspark-flow XAudioProcessor / iOS AudioProcessor):
 * - Owns a HandlerThread (equivalent to boost::asio::io_context + thread / GCD serial queue)
 * - Capture thread calls pushSamples() which copies data and posts to encoding thread
 * - All mutable state (pendingSamples, encoder, level, sequenceNumber) only accessed
 *   on the HandlerThread — no locks needed
 * - audioStarted/audioEnd events are emitted from the encoding thread,
 *   so preSkip/sequenceNumber are read without cross-thread risk
 */
class AudioProcessor(private val config: AudioConfig) {
  companion object {
    private const val TAG = "AudioProcessor"
  }

  // Encoding thread (equivalent to boost::asio::io_context + thread)
  private var handlerThread: HandlerThread? = null
  private var handler: Handler? = null

  // All fields below are only accessed on handlerThread — no locks needed
  private var opusEncoder: OpusEncoder? = null
  private val pendingSamples = mutableListOf<Short>()
  private val samplesPerFrame: Int = (config.sampleRate * config.frameSize / 1000.0).toInt()
  private val framesPerPacket: Int = Math.max(1, (config.packetDuration / config.frameSize).toInt())
  private var packetBuffer = java.io.ByteArrayOutputStream()  // accumulates encoded frames
  private var packetFrameCount: Int = 0
  private var sequenceNumber: Int = 0
  private var startTime: Double = 0.0

  // Audio level: accumulate RMS over ~360ms window
  private var levelSumSquares: Double = 0.0
  private var levelSampleCount: Int = 0
  private val levelUpdateSamples: Int = config.sampleRate * config.channels * config.audioLevelWindow / 1000
  private var currentLevel: Float = 0.0f

  // Debug file output
  private var pcmFileOutputStream: FileOutputStream? = null

  // Event callbacks (all invoked on encoding thread)
  // onAudioChunk: (data, timestamp, sequenceNumber, audioLevel, duration, frameCount)
  private var onAudioChunk: ((ByteArray, Double, Int, Float, Double, Int) -> Unit)? = null
  private var onStarted: ((timestamp: Double, sampleRate: Int, channels: Int, bitrate: Int, frameSize: Double, preSkip: Int) -> Unit)? = null
  private var onEnd: ((timestamp: Double, totalDuration: Double, totalPackets: Int) -> Unit)? = null

  /**
   * Start the encoding thread, create Opus encoder, emit audioStarted.
   * All encoder init + preSkip read happen on the same thread — no cross-thread risk.
   */
  fun start(debugFile: File? = null) {
    val thread = HandlerThread("OpusEncodingThread").apply { start() }
    handlerThread = thread
    handler = Handler(thread.looper)

    val ready = CountDownLatch(1)
    handler!!.post {
      // Init encoder on encoding thread
      _initEncoder()

      // Debug file
      if (debugFile != null) {
        try {
          pcmFileOutputStream = FileOutputStream(debugFile)
          Log.d(TAG, "Debug PCM file: ${debugFile.absolutePath}")
        } catch (e: Exception) {
          Log.e(TAG, "Failed to create debug file: ${e.message}")
        }
      }

      // Emit audioStarted on encoding thread — preSkip read is safe here
      startTime = System.currentTimeMillis().toDouble()
      val preSkip = opusEncoder?.preSkip ?: 0
      onStarted?.invoke(
        startTime,
        config.sampleRate,
        config.channels,
        config.bitrate,
        config.frameSize,
        preSkip
      )

      ready.countDown()
    }
    ready.await()

    Log.d(TAG, "Started: ${config.sampleRate}Hz, ${config.channels}ch, frame=$samplesPerFrame samples")
  }

  /**
   * Push raw PCM samples from capture thread (copy + post, no shared state).
   */
  fun pushSamples(samples: ShortArray, count: Int) {
    val buf = samples.copyOf(count)
    handler?.post {
      for (s in buf) {
        pendingSamples.add(s)
      }
      _processFrames()
    }
  }

  /**
   * Synchronously flush remaining audio, emit audioEnd, destroy encoder, stop thread.
   * All sequenceNumber/encoder access on encoding thread — no cross-thread risk.
   */
  fun flushAndStop() {
    val h = handler ?: return
    val done = CountDownLatch(1)
    h.post {
      _flushRemainingFrames()

      // Emit audioEnd on encoding thread — sequenceNumber read is safe here
      val stopTime = System.currentTimeMillis().toDouble()
      val totalDuration = stopTime - startTime
      onEnd?.invoke(stopTime, totalDuration, sequenceNumber)

      // Destroy encoder on the same thread that used it
      opusEncoder?.destroy()
      opusEncoder = null
      pendingSamples.clear()
      pcmFileOutputStream?.close()
      pcmFileOutputStream = null
      done.countDown()
    }
    done.await()

    handlerThread?.quitSafely()
    handlerThread = null
    handler = null

    Log.d(TAG, "Flushed and stopped")
  }

  // MARK: - Event callback setters

  fun setOnAudioChunk(callback: (ByteArray, Double, Int, Float, Double, Int) -> Unit) {
    this.onAudioChunk = callback
  }

  fun setOnStarted(callback: (timestamp: Double, sampleRate: Int, channels: Int, bitrate: Int, frameSize: Double, preSkip: Int) -> Unit) {
    this.onStarted = callback
  }

  fun setOnEnd(callback: (timestamp: Double, totalDuration: Double, totalPackets: Int) -> Unit) {
    this.onEnd = callback
  }

  // MARK: - Encoding thread internals (all below only called on HandlerThread)

  private fun _initEncoder() {
    opusEncoder = OpusEncoder(
      sampleRate = config.sampleRate,
      channels = config.channels,
      bitrate = config.bitrate,
      frameSizeMs = config.frameSize,
      dredDurationMs = config.dredDuration
    )
    Log.d(TAG, "Opus encoder created, preSkip=${opusEncoder?.preSkip}")
  }

  private fun _processFrames() {
    val encoder = opusEncoder ?: return

    while (pendingSamples.size >= samplesPerFrame) {
      val frameData = ShortArray(samplesPerFrame)
      for (i in 0 until samplesPerFrame) {
        frameData[i] = pendingSamples.removeFirst()
      }

      // Debug PCM file
      pcmFileOutputStream?.let { fos ->
        val bytes = ByteArray(frameData.size * 2)
        java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(frameData)
        fos.write(bytes)
      }

      // Encode single frame to Opus
      val opusData = try {
        encoder.encode(frameData, samplesPerFrame)
      } catch (e: Exception) {
        Log.e(TAG, "Opus encode error: ${e.message}")
        continue
      }

      if (opusData == null || opusData.isEmpty()) {
        Log.w(TAG, "Opus encode returned null/empty")
        continue
      }

      // Accumulate encoded frame into packet buffer
      packetBuffer.write(opusData)
      packetFrameCount++

      // Accumulate energy for RMS level
      for (sample in frameData) {
        val s = sample.toDouble() / 32768.0
        levelSumSquares += s * s
      }
      levelSampleCount += frameData.size

      if (levelSampleCount >= levelUpdateSamples) {
        val rms = Math.sqrt(levelSumSquares / levelSampleCount)
        val dB = 20.0 * Math.log10(Math.max(rms, 1e-10))
        val dbFloor = -35.0
        val dbCeiling = -6.0
        currentLevel = Math.max(0.0, Math.min(1.0, (dB - dbFloor) / (dbCeiling - dbFloor))).toFloat()
        levelSumSquares = 0.0
        levelSampleCount = 0
      }

      // Emit when we have enough frames for one packet (packetDuration)
      if (packetFrameCount >= framesPerPacket) {
        val timestampMs = System.currentTimeMillis().toDouble()
        val duration = packetFrameCount * config.frameSize
        onAudioChunk?.invoke(packetBuffer.toByteArray(), timestampMs, sequenceNumber, currentLevel, duration, packetFrameCount)
        sequenceNumber++
        packetBuffer.reset()
        packetFrameCount = 0
      }
    }
  }

  private fun _flushRemainingFrames() {
    val encoder = opusEncoder ?: return

    // Pad remaining PCM with silence to fill the last frame
    if (pendingSamples.isNotEmpty() && pendingSamples.size < samplesPerFrame) {
      while (pendingSamples.size < samplesPerFrame) {
        pendingSamples.add(0)
      }
    }

    // Encode remaining frames
    while (pendingSamples.size >= samplesPerFrame) {
      val frameData = ShortArray(samplesPerFrame)
      for (i in 0 until samplesPerFrame) {
        frameData[i] = pendingSamples.removeFirst()
      }

      val opusData = try {
        encoder.encode(frameData, samplesPerFrame)
      } catch (e: Exception) {
        continue
      }

      if (opusData == null || opusData.isEmpty()) continue
      packetBuffer.write(opusData)
      packetFrameCount++
    }

    // Flush any remaining packet buffer (even if less than framesPerPacket)
    if (packetBuffer.size() > 0) {
      val timestampMs = System.currentTimeMillis().toDouble()
      val duration = packetFrameCount * config.frameSize
      onAudioChunk?.invoke(packetBuffer.toByteArray(), timestampMs, sequenceNumber, currentLevel, duration, packetFrameCount)
      sequenceNumber++
      packetBuffer.reset()
      packetFrameCount = 0
    }
  }
}
