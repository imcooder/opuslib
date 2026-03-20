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
  /** Packet duration in milliseconds (typically 20-100ms) */
  packetDuration: number
  /** DRED recovery duration in milliseconds (0-100, default 100) - NEW in Opus 1.6 */
  dredDuration?: number
  /** Enable amplitude events for waveform visualization */
  enableAmplitudeEvents?: boolean
  /** Amplitude event interval in milliseconds (default 16) */
  amplitudeEventInterval?: number
  /** Audio level RMS window duration in milliseconds (default 360) */
  audioLevelWindow?: number
  /** Save debug PCM audio to file (development only) */
  saveDebugAudio?: boolean
}

/**
 * Audio chunk event payload (Opus-encoded data)
 */
export interface AudioChunkEvent {
  /** Opus-encoded audio data as ArrayBuffer */
  data: ArrayBuffer
  /** Timestamp in milliseconds */
  timestamp: number
  /** Sequence number (increments with each packet) */
  sequenceNumber: number
  /** Audio level normalized to 0.0~1.0 (mapped from dBFS, 0 = silence, 1 = loud) */
  audioLevel: number
  /** Duration of this packet in milliseconds (frameSize * frameCount) */
  duration: number
  /** Number of Opus frames in this packet */
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
