# @imcooder/opuslib

**Opus 1.6 audio encoding for React Native and Expo**

> **Fork Notice:** This project is forked from [Scdales/opuslib](https://github.com/Scdales/opuslib). We've made the following enhancements:
>
> **Threading & Stability**
> - **Dedicated encoding thread** — Audio capture and Opus encoding run on separate threads (copy+post pattern). Capture thread is never blocked by encoding. All encoder operations are on a single serial queue — no locks, no cross-thread crash risk. Fixes iOS crash caused by encoding on the real-time audio thread.
> - **Flush on stop** — Remaining PCM samples are padded with silence and encoded on stop, so no audio is lost at the end of a session.
>
> **New Events**
> - **`audioStarted` event** — Emitted from the encoding thread when streaming starts. Includes actual audio config and Opus encoder `preSkip` (`OPUS_GET_LOOKAHEAD`), so decoders know how many samples to skip.
>   ```typescript
>   Opuslib.addListener('audioStarted', (event) => {
>     // event.timestamp: 1711000000000    (ms since epoch)
>     // event.sampleRate: 16000           (Hz)
>     // event.channels: 1                 (mono)
>     // event.bitrate: 24000              (bps)
>     // event.frameSize: 20               (ms)
>     // event.preSkip: 312                (samples, decoder should skip)
>   });
>   ```
> - **`audioEnd` event** — Emitted from the encoding thread when streaming stops. Includes session summary.
>   ```typescript
>   Opuslib.addListener('audioEnd', (event) => {
>     // event.timestamp: 1711000005000    (ms since epoch)
>     // event.totalDuration: 5000         (ms, session length)
>     // event.totalPackets: 250           (total encoded packets)
>   });
>   ```
>
> **New Fields**
> - **`audioLevel`** — Each `audioChunk` event includes a normalized `audioLevel` (0.0~1.0), computed via configurable RMS sliding window (default 360ms) with dBFS-to-linear mapping (IEC 61606).
>   ```typescript
>   Opuslib.addListener('audioChunk', (event) => {
>     // event.data: ArrayBuffer            (Opus encoded packet)
>     // event.timestamp: 1711000000100     (ms since epoch)
>     // event.sequenceNumber: 5            (packet counter)
>     // event.audioLevel: 0.72            (0=silence, 1=loud)
>   });
>   ```
> - **`preSkip`** — Opus encoder lookahead in samples, returned in `audioStarted` event. Decoders should skip this many samples at the beginning of the stream.
>
> **New Config Options**
> - **`audioLevelWindow`** — RMS window duration in milliseconds for audio level calculation (default: 360ms). Shorter window = more responsive, longer window = smoother.
>   ```typescript
>   await Opuslib.startStreaming({
>     sampleRate: 16000,
>     channels: 1,
>     bitrate: 24000,
>     frameSize: 20,
>     packetDuration: 20,
>     audioLevelWindow: 200,  // 200ms window (default: 360ms)
>   });
>   ```

Real-time audio capture and encoding using the latest Opus 1.6 codec, built from source with full native integration for iOS and Android.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

---

## Features

- **Opus 1.6** - Latest codec version compiled from the [official source](https://opus-codec.org/release/stable/2025/12/15/libopus-1_6.html)
- **Low Latency** - Real-time encoding with minimal overhead
- **Native Performance** - Direct C/C++ integration, no JavaScript encoding
- **Thread-safe Encoding** - Dedicated encoding thread, capture thread never blocked
- **Audio Level Metering** - Real-time 0~1 audio level in each audio chunk (360ms RMS window)
- **Lifecycle Events** - `audioStarted` / `audioEnd` events with session metadata
- **High Quality** - 24kbps achieves excellent speech quality
- **Cross-Platform** - iOS and Android with a consistent API
- **Zero Dependencies** - Self-contained with vendored Opus source
- **Configurable** - Bitrate, sample rate, frame size
- **Event-Based** - Stream encoded audio chunks via events

### Why Opus 1.6?

Opus is the gold standard for real-time voice applications:

- **Better compression** than AAC, MP3, or Vorbis at low bitrates
- **Lower latency** than other codecs (as low as 5ms)
- **Royalty-free** and open source
- **Internet standard** (RFC 6716) used by Discord, WhatsApp, WebRTC

---

## Installation

```bash
# Using npm
npm install @imcooder/opuslib

# Using yarn
yarn add @imcooder/opuslib

# Using pnpm
pnpm add @imcooder/opuslib
```

### Additional Setup

#### For Expo Projects

```bash
npx expo install @imcooder/opuslib
npx expo prebuild
```

#### For React Native CLI

```bash
# iOS
cd ios && pod install && cd ..

# Android - no additional steps needed
```

---

## Quick Start

```typescript
import Opuslib from '@imcooder/opuslib';
import { Platform, PermissionsAndroid } from 'react-native';

// Request microphone permission (Android)
async function requestPermission() {
  if (Platform.OS === 'android') {
    const granted = await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.RECORD_AUDIO
    );
    return granted === PermissionsAndroid.RESULTS.GRANTED;
  }
  return true; // iOS handles permissions automatically
}

// Start recording and encoding
async function startRecording() {
  const hasPermission = await requestPermission();
  if (!hasPermission) {
    console.error('Microphone permission denied');
    return;
  }

  // Listen for session lifecycle
  Opuslib.addListener('audioStarted', (event) => {
    console.log(`Started: ${event.sampleRate}Hz, preSkip=${event.preSkip}`);
  });

  Opuslib.addListener('audioEnd', (event) => {
    console.log(`Ended: ${event.totalDuration}ms, ${event.totalPackets} packets`);
  });

  // Listen for encoded audio chunks
  const subscription = Opuslib.addListener('audioChunk', (event) => {
    const { data, timestamp, sequenceNumber, audioLevel } = event;
    console.log(`Opus packet: ${data.byteLength} bytes, level=${audioLevel.toFixed(2)}`);

    // Send to your backend, save to file, etc.
  });

  // Start streaming
  await Opuslib.startStreaming({
    sampleRate: 16000,      // 16 kHz
    channels: 1,            // Mono
    bitrate: 24000,         // 24 kbps
    frameSize: 20,          // 20ms frames
    packetDuration: 20,     // 20ms packets
  });
}

// Stop recording
async function stopRecording() {
  await Opuslib.stopStreaming();
}
```

---

## API Reference

### Methods

#### `startStreaming(config: AudioConfig): Promise<void>`

Start audio capture and Opus encoding.

**Parameters:**

```typescript
interface AudioConfig {
  sampleRate: number;               // Sample rate in Hz (8000, 16000, 24000, 48000)
  channels: number;                 // Number of channels (1 = mono, 2 = stereo)
  bitrate: number;                  // Target bitrate in bits/second (e.g., 24000)
  frameSize: number;                // Frame duration in ms (2.5, 5, 10, 20, 40, 60)
  packetDuration: number;           // Packet duration in ms (multiple of frameSize)
  dredDuration?: number;            // Reserved for future DRED support (default: 0)
  audioLevelWindow?: number;        // RMS window duration in ms for audioLevel (default: 360)
  enableAmplitudeEvents?: boolean;  // Enable amplitude monitoring (default: false)
  amplitudeEventInterval?: number;  // Amplitude update interval in ms (default: 16)
}
```

**Recommended Settings for Speech:**

```typescript
{
  sampleRate: 16000,     // 16 kHz - optimal for speech
  channels: 1,           // Mono - sufficient for voice
  bitrate: 24000,        // 24 kbps - excellent quality
  frameSize: 20,         // 20ms - standard for real-time
  packetDuration: 20,    // 20ms - low latency
}
```

**Throws:** Error if already streaming or if microphone permission denied

---

#### `stopStreaming(): Promise<void>`

Stop audio capture and encoding, flush remaining audio, release resources.

---

#### `pauseStreaming(): void`

Pause audio capture (keeps resources allocated). Call `resumeStreaming()` to continue.

---

#### `resumeStreaming(): void`

Resume audio capture after calling `pauseStreaming()`.

---

### Events

#### `audioStarted`

Emitted when audio streaming successfully starts. Fired from the encoding thread so all values (including `preSkip`) are read without cross-thread risk.

```typescript
Opuslib.addListener('audioStarted', (event: AudioStartedEvent) => {
  console.log(`Streaming started at ${event.sampleRate}Hz, preSkip=${event.preSkip}`);
});
```

**Event Data:**

```typescript
interface AudioStartedEvent {
  timestamp: number;    // Milliseconds since epoch
  sampleRate: number;   // Actual sample rate in Hz
  channels: number;     // Number of channels
  bitrate: number;      // Configured bitrate in bits/second
  frameSize: number;    // Frame duration in milliseconds
  preSkip: number;      // Opus encoder lookahead in samples (decoder should skip these)
}
```

---

#### `audioChunk`

Emitted when an encoded Opus packet is ready.

```typescript
Opuslib.addListener('audioChunk', (event: AudioChunkEvent) => {
  // event.data: ArrayBuffer - Raw Opus packet (ready to send/save)
  // event.audioLevel: number - Audio level 0.0~1.0 (0=silence, 1=loud)
});
```

**Event Data:**

```typescript
interface AudioChunkEvent {
  data: ArrayBuffer;         // Raw Opus-encoded audio packet
  timestamp: number;         // Milliseconds since epoch
  sequenceNumber: number;    // Incrementing packet counter
  audioLevel: number;        // Audio level 0.0~1.0 (360ms RMS window, 0=silence, 1=loud)
}
```

---

#### `audioEnd`

Emitted when audio streaming stops. Fired from the encoding thread after flushing remaining audio.

```typescript
Opuslib.addListener('audioEnd', (event: AudioEndEvent) => {
  console.log(`Session ended: ${event.totalDuration}ms, ${event.totalPackets} packets`);
});
```

**Event Data:**

```typescript
interface AudioEndEvent {
  timestamp: number;      // Milliseconds since epoch
  totalDuration: number;  // Total session duration in milliseconds
  totalPackets: number;   // Total number of packets encoded
}
```

---

#### `amplitude`

Emitted periodically with audio amplitude data (requires `enableAmplitudeEvents: true`).

```typescript
Opuslib.addAmplitudeListener((event: AmplitudeEvent) => {
  // event.rms: number - Root mean square amplitude (0.0 - 1.0)
  // event.peak: number - Peak amplitude (0.0 - 1.0)
  // event.timestamp: number - Milliseconds since epoch
});
```

---

#### `error`

Emitted when an error occurs during recording.

```typescript
Opuslib.addErrorListener((event: ErrorEvent) => {
  console.error(`Error: ${event.message}`);
});
```

---

## Architecture

```
Capture Thread                  Encoding Thread (serial queue)
  |                               |
  | AVAudioEngine tap (iOS)       |
  | AudioRecord.read() (Android)  |
  |                               |
  | format convert + copy PCM     |
  |---- post(samples) ----------->| pendingSamples.append(samples)
  |                               | while (enough samples) {
  |                               |   opus_encode()
  |                               |   audioLevel calc (360ms RMS)
  |                               |   emit audioChunk event
  |                               | }
  |                               |
  | (stop)                        |
  |---- syncFlush() ------------->| pad silence + encode last frame
  |                               | emit audioEnd event
  |                               | destroy encoder
  |<---- done --------------------|
```

**iOS:** `DispatchQueue` (serial) as encoding thread, `AVAudioEngine` tap for capture

**Android:** `HandlerThread` + `Handler` as encoding thread, `AudioRecord` loop for capture

All encoder state (samples buffer, Opus encoder, audio level, sequence number) is only accessed on the encoding thread. No locks needed.

### Opus Build Configuration

The module compiles Opus 1.6 from source with the following CMake flags:

```cmake
-DCMAKE_BUILD_TYPE=Release
-DOPUS_DRED=OFF                    # DRED disabled (future feature)
-DOPUS_BUILD_SHARED_LIBRARY=OFF    # Static linking
-DOPUS_BUILD_TESTING=OFF           # No tests
-DOPUS_BUILD_PROGRAMS=OFF          # No CLI tools
```

**iOS:** Built as universal binary (arm64 + x86_64) for device and simulator

**Android:** Built for arm64-v8a, armeabi-v7a, and x86_64

---

## Platform Notes

### iOS

- **Minimum iOS Version:** 15.1+
- **Audio Session:** Automatically configured for recording
- **Permissions:** Add to `app.json`:

  ```json
  {
    "expo": {
      "ios": {
        "infoPlist": {
          "NSMicrophoneUsageDescription": "This app needs microphone access to record audio."
        }
      }
    }
  }
  ```

### Android

- **Minimum SDK:** API 24 (Android 7.0)
- **Permissions:** Automatically added to manifest, request at runtime:

  ```typescript
  import { PermissionsAndroid } from 'react-native';

  const granted = await PermissionsAndroid.request(
    PermissionsAndroid.PERMISSIONS.RECORD_AUDIO
  );
  ```

---

## Troubleshooting

### iOS: "Microphone permission not granted"

Add `NSMicrophoneUsageDescription` to your `Info.plist` or `app.json`.

### Android: "Microphone permission not granted"

Request permission at runtime before calling `startStreaming()`.

### Build Errors on iOS

Clean and reinstall pods:

```bash
cd ios
rm -rf Pods Podfile.lock opus-build
pod install
cd ..
```

### Build Errors on Android

Clean Gradle caches:

```bash
cd android
./gradlew clean
rm -rf .cxx build
cd ..
```

---

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting PRs.

### Development Setup

```bash
git clone https://github.com/imcooder/opuslib.git
cd opuslib
npm install
npm run build

cd example
npm install
npx expo run:ios    # or run:android
```

---

## License

MIT License - see [LICENSE](LICENSE) file for details

---

## Credits

- **Original Project** - [Scdales/opuslib](https://github.com/Scdales/opuslib)
- **Opus Codec** - [opus-codec.org](https://opus-codec.org/)
- **Expo Modules** - [docs.expo.dev](https://docs.expo.dev/modules/)

---

## Support

- **Issues:** [GitHub Issues](https://github.com/imcooder/opuslib/issues)
