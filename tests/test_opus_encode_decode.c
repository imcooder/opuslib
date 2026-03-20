/**
 * Opus encode/decode round-trip test
 *
 * Verifies that opus compiled correctly by:
 * 1. Creating encoder & decoder
 * 2. Encoding synthetic PCM (sine wave)
 * 3. Decoding back to PCM
 * 4. Checking output is non-silent (round-trip works)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <opus.h>

#define SAMPLE_RATE 16000
#define CHANNELS 1
#define FRAME_MS 20
#define FRAME_SIZE (SAMPLE_RATE * FRAME_MS / 1000)  /* 320 samples */
#define BITRATE 24000
#define MAX_PACKET 4000
#define NUM_FRAMES 50
#define PI 3.14159265358979323846

static void generate_sine(opus_int16 *pcm, int frame_size, int frame_index) {
    double freq = 440.0; /* A4 */
    int offset = frame_index * frame_size;
    for (int i = 0; i < frame_size; i++) {
        double t = (double)(offset + i) / SAMPLE_RATE;
        pcm[i] = (opus_int16)(sin(2.0 * PI * freq * t) * 16000);
    }
}

int main(void) {
    int err;

    /* --- Test 1: Create encoder --- */
    printf("Test 1: Create encoder... ");
    OpusEncoder *enc = opus_encoder_create(SAMPLE_RATE, CHANNELS, OPUS_APPLICATION_VOIP, &err);
    if (err != OPUS_OK || !enc) {
        printf("FAIL (error %d)\n", err);
        return 1;
    }
    opus_encoder_ctl(enc, OPUS_SET_BITRATE(BITRATE));
    printf("OK\n");

    /* --- Test 2: Create decoder --- */
    printf("Test 2: Create decoder... ");
    OpusDecoder *dec = opus_decoder_create(SAMPLE_RATE, CHANNELS, &err);
    if (err != OPUS_OK || !dec) {
        printf("FAIL (error %d)\n", err);
        return 1;
    }
    printf("OK\n");

    /* --- Test 3: Encode multiple frames --- */
    printf("Test 3: Encode %d frames... ", NUM_FRAMES);
    opus_int16 pcm_in[FRAME_SIZE];
    unsigned char packet[MAX_PACKET];
    int total_bytes = 0;

    /* Store packets for decoding */
    unsigned char packets[NUM_FRAMES][MAX_PACKET];
    int packet_sizes[NUM_FRAMES];

    for (int i = 0; i < NUM_FRAMES; i++) {
        generate_sine(pcm_in, FRAME_SIZE, i);
        int nbytes = opus_encode(enc, pcm_in, FRAME_SIZE, packets[i], MAX_PACKET);
        if (nbytes < 0) {
            printf("FAIL at frame %d (error %d: %s)\n", i, nbytes, opus_strerror(nbytes));
            return 1;
        }
        packet_sizes[i] = nbytes;
        total_bytes += nbytes;
    }
    printf("OK (total %d bytes, avg %.1f bytes/frame)\n", total_bytes, (double)total_bytes / NUM_FRAMES);

    /* --- Test 4: Decode and verify round-trip --- */
    printf("Test 4: Decode and verify... ");
    opus_int16 pcm_out[FRAME_SIZE];
    int nonzero_samples = 0;

    for (int i = 0; i < NUM_FRAMES; i++) {
        int decoded = opus_decode(dec, packets[i], packet_sizes[i], pcm_out, FRAME_SIZE, 0);
        if (decoded < 0) {
            printf("FAIL at frame %d (error %d: %s)\n", i, decoded, opus_strerror(decoded));
            return 1;
        }
        if (decoded != FRAME_SIZE) {
            printf("FAIL at frame %d (expected %d samples, got %d)\n", i, FRAME_SIZE, decoded);
            return 1;
        }
        for (int j = 0; j < decoded; j++) {
            if (pcm_out[j] != 0) nonzero_samples++;
        }
    }

    if (nonzero_samples == 0) {
        printf("FAIL (decoded audio is all zeros)\n");
        return 1;
    }
    printf("OK (%d non-zero samples)\n", nonzero_samples);

    /* --- Test 5: Verify opus version --- */
    printf("Test 5: Opus version... %s\n", opus_get_version_string());

    /* Cleanup */
    opus_encoder_destroy(enc);
    opus_decoder_destroy(dec);

    printf("\nAll tests passed!\n");
    return 0;
}
