import AVFoundation
import ExpoModulesCore

/**
 * AudioEngineManager - Manages AVAudioEngine for real-time audio capture.
 *
 * Architecture (matches genspark-flow MicrophoneCapture / Android AudioRecordManager):
 * - This class ONLY handles audio capture (AVAudioEngine lifecycle + tap callback)
 * - Encoding is delegated to AudioProcessor (separate serial DispatchQueue)
 * - Tap callback calls processor.pushSamples() which is copy + post (no blocking)
 */
class AudioEngineManager {
  // Audio engine and nodes
  private var audioEngine: AVAudioEngine?
  private var inputNode: AVAudioInputNode?

  // Audio format converter
  private var audioConverter: AVAudioConverter?

  // Encoding processor (owns encoder, runs on separate serial queue)
  private var processor: AudioProcessor?

  // Configuration (immutable after init)
  private let config: AudioConfig

  // Recording state
  private var isRecording = false
  private var isPaused = false
  private var loggedFirstBuffer = false

  // Event callbacks
  private var onAudioChunk: ((Data, Double, Int, Float) -> Void)?
  private var onStarted: ((_ timestamp: Double, _ sampleRate: Int, _ channels: Int, _ bitrate: Int, _ frameSize: Double, _ preSkip: Int) -> Void)?
  private var onEnd: ((_ timestamp: Double, _ totalDuration: Double, _ totalPackets: Int) -> Void)?
  private var onAmplitude: ((Float, Float, Double) -> Void)?
  private var onError: ((Error) -> Void)?

  init(config: AudioConfig) {
    self.config = config

    // Register for interruption notifications
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
  }

  // MARK: - Public Methods

  func start() throws {
    guard !isRecording else {
      throw AudioStreamError.alreadyStreaming
    }

    // Configure audio session
    try configureAudioSession()

    // Create and start AudioProcessor (encoding thread)
    let proc = AudioProcessor(config: config)
    proc.setOnAudioChunk { [weak self] data, timestamp, seq, level in
      self?.onAudioChunk?(data, timestamp, seq, level)
    }
    proc.setOnStarted { [weak self] timestamp, sampleRate, channels, bitrate, frameSize, preSkip in
      self?.onStarted?(timestamp, sampleRate, channels, bitrate, frameSize, preSkip)
    }
    proc.setOnEnd { [weak self] timestamp, totalDuration, totalPackets in
      self?.onEnd?(timestamp, totalDuration, totalPackets)
    }

    // Debug file
    var debugURL: URL? = nil
    if config.saveDebugAudio == true {
      let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      let timestamp = Date().timeIntervalSince1970
      debugURL = documentsPath.appendingPathComponent("debug_pcm_\(timestamp).raw")
    }

    try proc.start(debugFileURL: debugURL)
    processor = proc

    // Create and configure AVAudioEngine
    audioEngine = AVAudioEngine()
    guard let audioEngine = audioEngine else {
      throw AudioStreamError.audioEngineError("Failed to create AVAudioEngine")
    }

    inputNode = audioEngine.inputNode
    guard let inputNode = inputNode else {
      throw AudioStreamError.audioEngineError("Failed to get input node")
    }

    let hardwareFormat = inputNode.outputFormat(forBus: 0)
    print("[AudioEngineManager] Hardware format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount)ch")

    guard let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(config.sampleRate),
      channels: AVAudioChannelCount(config.channels),
      interleaved: true
    ) else {
      throw AudioStreamError.audioEngineError("Failed to create output format")
    }

    guard let converter = AVAudioConverter(from: hardwareFormat, to: outputFormat) else {
      throw AudioStreamError.audioEngineError("Failed to create audio converter")
    }
    audioConverter = converter
    print("[AudioEngineManager] Converter: \(hardwareFormat.sampleRate)Hz → \(outputFormat.sampleRate)Hz")

    let bufferSize: AVAudioFrameCount = 1024

    // Install tap — real-time thread callback, only does format convert + copy + post
    inputNode.installTap(
      onBus: 0,
      bufferSize: bufferSize,
      format: hardwareFormat
    ) { [weak self] buffer, time in
      self?.onTapBuffer(buffer)
    }

    try audioEngine.start()
    isRecording = true

    print("[AudioEngineManager] Started: \(hardwareFormat.sampleRate)Hz → \(config.sampleRate)Hz, \(config.channels)ch")
  }

  func stop() {
    guard isRecording else { return }

    isRecording = false

    // Stop audio capture
    inputNode?.removeTap(onBus: 0)
    audioEngine?.stop()

    // Flush and stop encoding thread (synchronous — drains remaining samples)
    processor?.flushAndStop()
    processor = nil

    // Clean up
    audioEngine = nil
    inputNode = nil
    audioConverter = nil

    print("[AudioEngineManager] Stopped")
  }

  func pause() {
    isPaused = true
    print("[AudioEngineManager] Paused")
  }

  func resume() {
    isPaused = false
    print("[AudioEngineManager] Resumed")
  }

  // MARK: - Event Handlers

  func setOnAudioChunk(_ callback: @escaping (Data, Double, Int, Float) -> Void) {
    self.onAudioChunk = callback
  }

  func setOnStarted(_ callback: @escaping (_ timestamp: Double, _ sampleRate: Int, _ channels: Int, _ bitrate: Int, _ frameSize: Double, _ preSkip: Int) -> Void) {
    self.onStarted = callback
  }

  func setOnEnd(_ callback: @escaping (_ timestamp: Double, _ totalDuration: Double, _ totalPackets: Int) -> Void) {
    self.onEnd = callback
  }

  func setOnAmplitude(_ callback: @escaping (Float, Float, Double) -> Void) {
    self.onAmplitude = callback
  }

  func setOnError(_ callback: @escaping (Error) -> Void) {
    self.onError = callback
  }

  // MARK: - Real-time Audio Thread (tap callback)
  // Only does format conversion + copy + post. No encoding, no locks.

  private func onTapBuffer(_ buffer: AVAudioPCMBuffer) {
    guard !isPaused else { return }
    guard let audioConverter = audioConverter else { return }

    let sampleRateRatio = Double(config.sampleRate) / buffer.format.sampleRate
    let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio)

    guard let outputFormat = audioConverter.outputFormat as? AVAudioFormat,
          let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
          ) else { return }

    var error: NSError?
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }

    let status = audioConverter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
    if status == .error { return }

    guard let channelData = convertedBuffer.int16ChannelData else { return }

    let frameLength = Int(convertedBuffer.frameLength)
    let channelDataPointer = channelData[0]

    if !loggedFirstBuffer {
      print("[AudioEngineManager] First buffer: \(frameLength) samples at \(convertedBuffer.format.sampleRate)Hz")
      loggedFirstBuffer = true
    }

    // Copy PCM + post to encoding queue (like genspark-flow pushSamples / boost::asio::post)
    let samples = Array(UnsafeBufferPointer(start: channelDataPointer, count: frameLength))
    processor?.pushSamples(samples)
  }

  // MARK: - Audio Session

  private func configureAudioSession() throws {
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.record, mode: .measurement, options: [])
    try audioSession.setPreferredSampleRate(Double(config.sampleRate))
    try audioSession.setPreferredIOBufferDuration(config.frameSize / 1000.0)
    try audioSession.setActive(true)
    print("[AudioEngineManager] Audio session configured")
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

    switch type {
    case .began:
      print("[AudioEngineManager] Audio interruption began")
      pause()
    case .ended:
      print("[AudioEngineManager] Audio interruption ended")
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) { resume() }
      }
    @unknown default:
      break
    }
  }

  deinit {
    stop()
    NotificationCenter.default.removeObserver(self)
  }
}
