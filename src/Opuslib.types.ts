/**
 * Audio configuration for Opus encoding
 */
export interface AudioConfig {
  /** Sample rate in Hz (8000, 12000, 16000, 24000, 48000) */
  sampleRate: number
  /** Number of channels (1 = mono, 2 = stereo) */
  channels: number
  /** Target bitrate in bits/second (e.g., 24000 for 24kbps) */
  bitrate: number
  /** Frame duration in milliseconds (2.5, 5, 10, 20, 40, 60) */
  frameSize: number
  /** Number of Opus frames per callback (default 1). Multiple frames are returned as independent packets in frames[], reducing JS bridge calls */
  framesPerCallback?: number
  /** DRED recovery duration in milliseconds (0-100, default 100) - NEW in Opus 1.6 */
  dredDuration?: number
  /** Enable amplitude events for waveform visualization */
  enableAmplitudeEvents?: boolean
  /** Amplitude event interval in milliseconds (default 16) */
  amplitudeEventInterval?: number
  /** Enable per-frame audio level calculation (default false). When enabled, each OpusFrame includes audioLevel */
  enableAudioLevel?: boolean
  /** Save debug PCM audio to file (development only) */
  saveDebugAudio?: boolean
  /**
   * iOS AudioSession configuration (iOS only, ignored on Android/Web).
   * If omitted, defaults to { category: 'record', mode: 'measurement', options: [] }
   */
  iosAudioSession?: {
    /**
     * AVAudioSession.Category
     * - 'record': Pure recording (default)
     * - 'playAndRecord': Record + play simultaneously
     * - 'playback': Playback only
     * - 'ambient': Mix with other audio, no interruption
     */
    category: 'record' | 'playAndRecord' | 'playback' | 'ambient'
    /**
     * AVAudioSession.Mode
     * - 'default': Default mode (AGC, echo cancellation enabled)
     * - 'voiceChat': Optimized for voice calls
     * - 'measurement': Disable system audio processing (default)
     * - 'spokenAudio': Optimized for spoken content
     */
    mode: 'default' | 'voiceChat' | 'measurement' | 'spokenAudio'
    /**
     * AVAudioSession.CategoryOptions (combinable)
     * - 'mixWithOthers': Allow mixing with other audio apps
     * - 'defaultToSpeaker': Route to speaker instead of earpiece
     * - 'allowBluetooth': Allow Bluetooth HFP devices
     * - 'allowAirPlay': Allow AirPlay output
     * - 'allowBluetoothA2DP': Allow Bluetooth A2DP (high quality audio)
     */
    options?: Array<'mixWithOthers' | 'defaultToSpeaker' | 'allowBluetooth' | 'allowAirPlay' | 'allowBluetoothA2DP'>
  }
}

/**
 * A single Opus frame — one complete opus_encode() output with its own TOC byte
 */
export interface OpusFrame {
  /** Opus-encoded packet data (independent, decodable) */
  data: ArrayBuffer
  /** Per-frame audio level 0.0~1.0 (only present when enableAudioLevel is true) */
  audioLevel?: number
}

/**
 * Audio chunk event payload (Opus-encoded data)
 */
export interface AudioChunkEvent {
  /** Array of independent Opus frames. Each frame is a complete opus_encode() output, decodable on its own */
  frames: OpusFrame[]
  /** Timestamp in milliseconds */
  timestamp: number
  /** Sequence number (increments with each callback) */
  sequenceNumber: number
  /** Duration of all frames in milliseconds (frameSize * frameCount) */
  duration: number
  /** Number of Opus frames in this callback (= frames.length) */
  frameCount: number
}

/**
 * Amplitude event payload (for waveform visualization)
 */
export interface AmplitudeEvent {
  /** Root mean square amplitude (0.0 - 1.0) */
  rms: number
  /** Peak amplitude (0.0 - 1.0) */
  peak: number
  /** Timestamp in milliseconds */
  timestamp: number
}

/**
 * Audio started event payload
 * Emitted when audio streaming successfully starts
 */
export interface AudioStartedEvent {
  /** Timestamp in milliseconds when streaming started */
  timestamp: number
  /** Actual sample rate being used */
  sampleRate: number
  /** Number of channels */
  channels: number
  /** Configured bitrate in bits/second */
  bitrate: number
  /** Frame duration in milliseconds */
  frameSize: number
  /** Opus encoder lookahead in samples (decoder should skip this many samples at start) */
  preSkip: number
}

/**
 * Audio end event payload
 * Emitted when audio streaming stops
 */
export interface AudioEndEvent {
  /** Timestamp in milliseconds when streaming stopped */
  timestamp: number
  /** Total duration of the streaming session in milliseconds */
  totalDuration: number
  /** Total number of packets encoded during the session */
  totalPackets: number
}

/**
 * Error event payload
 */
export interface ErrorEvent {
  /** Error code */
  code: string
  /** Error message */
  message: string
}

/**
 * Event subscription
 */
export interface Subscription {
  remove: () => void
}
