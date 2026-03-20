import { useState, useRef } from 'react';
import Opuslib from '@imcooder/opuslib';
import type { Subscription } from '@imcooder/opuslib';
import { Button, SafeAreaView, ScrollView, Text, View, StyleSheet, Platform, PermissionsAndroid } from 'react-native';

export default function App() {
  const [isRecording, setIsRecording] = useState(false);
  const [packetCount, setPacketCount] = useState(0);
  const [totalBytes, setTotalBytes] = useState(0);
  const [audioLevel, setAudioLevel] = useState(0);
  const [preSkip, setPreSkip] = useState(0);
  const [sessionDuration, setSessionDuration] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const subscriptions = useRef<Subscription[]>([]);

  const startRecording = async () => {
    try {
      setError(null);
      setPacketCount(0);
      setTotalBytes(0);
      setAudioLevel(0);
      setPreSkip(0);
      setSessionDuration(0);

      // Request microphone permission on Android
      if (Platform.OS === 'android') {
        const granted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
          {
            title: 'Microphone Permission',
            message: 'This app needs access to your microphone to record audio.',
            buttonNeutral: 'Ask Me Later',
            buttonNegative: 'Cancel',
            buttonPositive: 'OK',
          }
        );
        if (granted !== PermissionsAndroid.RESULTS.GRANTED) {
          setError('Microphone permission denied');
          return;
        }
      }

      // Subscribe to audioStarted
      subscriptions.current.push(
        Opuslib.addListener('audioStarted', (event) => {
          setPreSkip(event.preSkip);
          console.log(`[audioStarted] ${event.sampleRate}Hz, ${event.channels}ch, ${event.bitrate}bps, preSkip=${event.preSkip}`);
        })
      );

      // Subscribe to audioEnd
      subscriptions.current.push(
        Opuslib.addListener('audioEnd', (event) => {
          setSessionDuration(event.totalDuration);
          console.log(`[audioEnd] duration=${event.totalDuration}ms, packets=${event.totalPackets}`);
        })
      );

      // Subscribe to audio chunks
      subscriptions.current.push(
        Opuslib.addListener('audioChunk', (event) => {
          const bytes = event.frames.reduce((sum, f) => sum + f.data.byteLength, 0);
          setPacketCount((prev) => prev + event.frameCount);
          setTotalBytes((prev) => prev + bytes);
          // Use last frame's audioLevel (if enableAudioLevel is true)
          const lastLevel = event.frames[event.frames.length - 1]?.audioLevel ?? 0;
          setAudioLevel(lastLevel);
          console.log(`[audioChunk] #${event.sequenceNumber}: ${event.frameCount} frames, ${bytes}B, level=${lastLevel.toFixed(2)}, duration=${event.duration}ms`);
        })
      );

      // Subscribe to errors
      subscriptions.current.push(
        Opuslib.addListener('error', (event) => {
          setError(event.message);
          console.error(`[error] ${event.code}: ${event.message}`);
        })
      );

      // Start streaming
      await Opuslib.startStreaming({
        sampleRate: 16000,
        channels: 1,
        bitrate: 24000,
        frameSize: 20,
        framesPerCallback: 5,
        enableAudioLevel: true,
      });

      setIsRecording(true);
      console.log('Recording started');
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      console.error('Failed to start recording:', err);
    }
  };

  const stopRecording = async () => {
    try {
      await Opuslib.stopStreaming();

      // Clean up subscriptions
      subscriptions.current.forEach((sub) => sub.remove());
      subscriptions.current = [];

      setIsRecording(false);
      console.log('Recording stopped');
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      console.error('Failed to stop recording:', err);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scrollView}>
        <Text style={styles.header}>Opus 1.6 Audio Encoding</Text>
        <Text style={styles.subtitle}>@imcooder/opuslib Example</Text>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Configuration</Text>
          <InfoRow label="Sample Rate" value="16 kHz" />
          <InfoRow label="Bitrate" value="24 kbps" />
          <InfoRow label="Channels" value="Mono" />
          <InfoRow label="Frame Size" value="20 ms" />
          <InfoRow label="Frames/Callback" value="5 (reduces bridge calls)" />
          <InfoRow label="Audio Level" value="per-frame (enabled)" />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Controls</Text>
          <Button
            title={isRecording ? 'Stop Recording' : 'Start Recording'}
            onPress={isRecording ? stopRecording : startRecording}
            color={isRecording ? '#ff3b30' : '#007aff'}
          />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Statistics</Text>
          <InfoRow label="Status" value={isRecording ? 'Recording' : 'Stopped'} />
          <InfoRow label="Pre-skip" value={`${preSkip} samples`} />
          <InfoRow label="Packets Received" value={packetCount.toString()} />
          <InfoRow label="Total Bytes" value={`${totalBytes.toLocaleString()} bytes`} />
          {totalBytes > 0 && (
            <InfoRow
              label="Avg Packet Size"
              value={`${Math.round(totalBytes / packetCount)} bytes`}
            />
          )}
          <InfoRow label="Audio Level" value={`${(audioLevel * 100).toFixed(0)}%`} />
          {sessionDuration > 0 && (
            <InfoRow label="Session Duration" value={`${(sessionDuration / 1000).toFixed(1)}s`} />
          )}
        </View>

        {/* Audio level bar */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Audio Level</Text>
          <View style={styles.levelBarBg}>
            <View style={[styles.levelBarFg, { width: `${Math.min(audioLevel * 100, 100)}%` }]} />
          </View>
        </View>

        {error && (
          <View style={[styles.section, styles.errorSection]}>
            <Text style={styles.sectionTitle}>Error</Text>
            <Text style={styles.errorText}>{error}</Text>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}:</Text>
      <Text style={styles.infoValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollView: {
    flex: 1,
  },
  header: {
    fontSize: 28,
    fontWeight: 'bold',
    textAlign: 'center',
    marginTop: 20,
    marginBottom: 5,
  },
  subtitle: {
    fontSize: 16,
    textAlign: 'center',
    color: '#666',
    marginBottom: 20,
  },
  section: {
    margin: 15,
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 15,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  errorSection: {
    backgroundColor: '#fff5f5',
    borderColor: '#ff3b30',
    borderWidth: 1,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  infoLabel: {
    fontSize: 14,
    color: '#666',
  },
  infoValue: {
    fontSize: 14,
    fontWeight: '500',
  },
  errorText: {
    color: '#ff3b30',
    fontSize: 14,
  },
  levelBarBg: {
    height: 20,
    backgroundColor: '#e0e0e0',
    borderRadius: 10,
    overflow: 'hidden',
  },
  levelBarFg: {
    height: '100%',
    backgroundColor: '#4cd964',
    borderRadius: 10,
  },
});
