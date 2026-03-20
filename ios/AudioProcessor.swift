import Foundation

/**
 * AudioProcessor - Dedicated encoding thread for Opus encoding and dispatch.
 *
 * Architecture (matches genspark-flow XAudioProcessor / Android AudioProcessor):
 * - Owns a serial DispatchQueue (equivalent to boost::asio::io_context + thread / HandlerThread)
 * - Capture thread calls pushSamples() which copies data and posts to encoding queue
 * - All mutable state (pendingSamples, encoder, level, sequenceNumber) only accessed
 *   on the encoding queue — no locks needed
 * - audioStarted/audioEnd events are emitted from the encoding queue,
 *   so preSkip/sequenceNumber are read without cross-thread risk
 */
class AudioProcessor {
  // Dedicated serial queue — equivalent to boost::asio::io_context + thread / HandlerThread
  private let queue = DispatchQueue(label: "com.opuslib.encoding", qos: .userInitiated)

  // All fields below are only accessed on queue — no locks needed
  private var opusEncoder: OpusEncoder?
  private var pendingSamples: [Int16] = []
  private let samplesPerFrame: Int
  private let framesPerPacket: Int  // how many frames to batch before emitting
  private var packetBuffer: Data = Data()  // accumulates encoded frames
  private var packetFrameCount: Int = 0
  private var sequenceNumber: Int = 0
  private var startTime: Double = 0

  // Audio level: accumulate RMS over ~360ms window
  private var levelSumSquares: Double = 0.0
  private var levelSampleCount: Int = 0
  private let levelUpdateSamples: Int
  private var currentLevel: Float = 0.0

  // Debug file
  private var pcmFileHandle: FileHandle?

  // Event callbacks (all invoked on encoding queue)
  // onAudioChunk: (data, timestamp, sequenceNumber, audioLevel, duration, frameCount)
  private var onAudioChunk: ((Data, Double, Int, Float, Double, Int) -> Void)?
  private var onStarted: ((_ timestamp: Double, _ sampleRate: Int, _ channels: Int, _ bitrate: Int, _ frameSize: Double, _ preSkip: Int) -> Void)?
  private var onEnd: ((_ timestamp: Double, _ totalDuration: Double, _ totalPackets: Int) -> Void)?

  // Configuration (immutable)
  private let config: AudioConfig

  init(config: AudioConfig) {
    self.config = config
    self.samplesPerFrame = Int(Double(config.sampleRate) * config.frameSize / 1000.0)
    self.framesPerPacket = max(1, Int(config.packetDuration / config.frameSize))
    let windowMs = config.audioLevelWindow ?? 360
    self.levelUpdateSamples = config.sampleRate * config.channels * windowMs / 1000
  }

  // MARK: - Public API

  /**
   * Start: create Opus encoder on encoding queue and emit audioStarted event.
   * All encoder init + preSkip read happen on the same thread — no cross-thread risk.
   */
  func start(debugFileURL: URL? = nil) throws {
    var initError: Error?
    queue.sync {
      do {
        self.opusEncoder = try OpusEncoder(
          sampleRate: self.config.sampleRate,
          channels: self.config.channels,
          bitrate: self.config.bitrate,
          frameSizeMs: self.config.frameSize,
          dredDurationMs: self.config.dredDuration ?? 100
        )
      } catch {
        initError = error
        return
      }

      // Debug file
      if let url = debugFileURL {
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        self.pcmFileHandle = try? FileHandle(forWritingTo: url)
      }

      // Emit audioStarted on encoding queue — preSkip read is safe here
      self.startTime = Date().timeIntervalSince1970 * 1000
      let preSkip = self.opusEncoder?.preSkip ?? 0
      self.onStarted?(
        self.startTime,
        self.config.sampleRate,
        self.config.channels,
        self.config.bitrate,
        self.config.frameSize,
        preSkip
      )
    }

    if let error = initError { throw error }

    print("[AudioProcessor] Started: \(config.sampleRate)Hz, frame=\(samplesPerFrame) samples")
  }

  /**
   * Push raw PCM samples from capture thread (copy + post, no shared state).
   */
  func pushSamples(_ samples: [Int16]) {
    queue.async { [weak self] in
      guard let self = self else { return }
      self.pendingSamples.append(contentsOf: samples)
      self._processFrames()
    }
  }

  /**
   * Synchronously flush remaining audio, emit audioEnd, destroy encoder.
   * All sequenceNumber/encoder access on encoding queue — no cross-thread risk.
   */
  func flushAndStop() {
    queue.sync {
      self._flushRemainingFrames()

      // Emit audioEnd on encoding queue — sequenceNumber read is safe here
      let stopTime = Date().timeIntervalSince1970 * 1000
      let totalDuration = stopTime - self.startTime
      self.onEnd?(stopTime, totalDuration, self.sequenceNumber)

      // Destroy encoder on the same thread that used it
      self.opusEncoder = nil
      self.pendingSamples.removeAll()
      self.pcmFileHandle?.closeFile()
      self.pcmFileHandle = nil
    }

    print("[AudioProcessor] Flushed and stopped")
  }

  // MARK: - Event callbacks

  func setOnAudioChunk(_ callback: @escaping (Data, Double, Int, Float, Double, Int) -> Void) {
    self.onAudioChunk = callback
  }

  func setOnStarted(_ callback: @escaping (_ timestamp: Double, _ sampleRate: Int, _ channels: Int, _ bitrate: Int, _ frameSize: Double, _ preSkip: Int) -> Void) {
    self.onStarted = callback
  }

  func setOnEnd(_ callback: @escaping (_ timestamp: Double, _ totalDuration: Double, _ totalPackets: Int) -> Void) {
    self.onEnd = callback
  }

  // MARK: - Encoding queue internals (all below only called on queue)

  private func _processFrames() {
    guard let opusEncoder = opusEncoder else { return }

    while pendingSamples.count >= samplesPerFrame {
      let frameData = Array(pendingSamples.prefix(samplesPerFrame))
      pendingSamples.removeFirst(samplesPerFrame)

      // Debug PCM file
      if let fileHandle = pcmFileHandle {
        frameData.withUnsafeBufferPointer { ptr in
          let data = Data(bytes: ptr.baseAddress!, count: frameData.count * MemoryLayout<Int16>.size)
          fileHandle.write(data)
        }
      }

      // Encode single frame to Opus
      var encodedPacket: Data?
      frameData.withUnsafeBufferPointer { bufferPointer in
        guard let baseAddress = bufferPointer.baseAddress else { return }
        encodedPacket = opusEncoder.encode(pcm: baseAddress, frameSize: samplesPerFrame)
      }

      guard let opusData = encodedPacket, !opusData.isEmpty else {
        print("[AudioProcessor] Failed to encode Opus packet")
        continue
      }

      // Accumulate encoded frame into packet buffer
      packetBuffer.append(opusData)
      packetFrameCount += 1

      // Accumulate energy for RMS level
      for sample in frameData {
        let s = Double(sample) / 32768.0
        levelSumSquares += s * s
      }
      levelSampleCount += frameData.count

      if levelSampleCount >= levelUpdateSamples {
        let rms = sqrt(levelSumSquares / Double(levelSampleCount))
        let dB = 20.0 * log10(max(rms, 1e-10))
        let dbFloor = -35.0
        let dbCeiling = -6.0
        currentLevel = Float(max(0.0, min(1.0, (dB - dbFloor) / (dbCeiling - dbFloor))))
        levelSumSquares = 0.0
        levelSampleCount = 0
      }

      // Emit when we have enough frames for one packet (packetDuration)
      if packetFrameCount >= framesPerPacket {
        let timestampMs = Date().timeIntervalSince1970 * 1000
        let duration = Double(packetFrameCount) * config.frameSize
        onAudioChunk?(packetBuffer, timestampMs, sequenceNumber, currentLevel, duration, packetFrameCount)
        sequenceNumber += 1
        packetBuffer = Data()
        packetFrameCount = 0
      }
    }
  }

  private func _flushRemainingFrames() {
    guard let opusEncoder = opusEncoder else { return }

    // Pad remaining PCM with silence to fill the last frame
    if !pendingSamples.isEmpty && pendingSamples.count < samplesPerFrame {
      pendingSamples.append(contentsOf: [Int16](repeating: 0, count: samplesPerFrame - pendingSamples.count))
    }

    // Encode remaining frames
    while pendingSamples.count >= samplesPerFrame {
      let frameData = Array(pendingSamples.prefix(samplesPerFrame))
      pendingSamples.removeFirst(samplesPerFrame)

      var encodedPacket: Data?
      frameData.withUnsafeBufferPointer { bufferPointer in
        guard let baseAddress = bufferPointer.baseAddress else { return }
        encodedPacket = opusEncoder.encode(pcm: baseAddress, frameSize: samplesPerFrame)
      }

      guard let opusData = encodedPacket, !opusData.isEmpty else { continue }
      packetBuffer.append(opusData)
      packetFrameCount += 1
    }

    // Flush any remaining packet buffer (even if less than framesPerPacket)
    if !packetBuffer.isEmpty {
      let timestampMs = Date().timeIntervalSince1970 * 1000
      let duration = Double(packetFrameCount) * config.frameSize
      onAudioChunk?(packetBuffer, timestampMs, sequenceNumber, currentLevel, duration, packetFrameCount)
      sequenceNumber += 1
      packetBuffer = Data()
      packetFrameCount = 0
    }
  }
}
