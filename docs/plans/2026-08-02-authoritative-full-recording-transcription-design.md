# Authoritative Full-Recording Transcription

## Problem

Murmur currently treats pause-bounded Whisper results as final transcript fragments and
joins them on release. Every audio sample is retained, but a segment can return plausible,
non-empty text that omits words. Because that result does not look like an error, the
fallback never runs and the final transcript can lose its middle or end.

The local history also contains pairs of different session IDs with identical start times.
The application bundle permits multiple instances, and its development launcher explicitly
requests a new instance. Two instances can therefore capture the same shortcut and insert
different results.

## Decision

The complete processed recording is the only authoritative transcription input. On key
release, Murmur stops capture, drains all frames already handed off by the audio input, and
runs one Whisper request over the full sample buffer. Pause-bounded decoding must not
contribute text to the final result.

The current ordered frame stream and quiescent audio-stop behavior remain in place because
they prevent a separate last-frame loss race. Segment detection may remain as isolated,
tested audio analysis, but the orchestrator will not enqueue segment transcription work or
assemble final text from it.

The packaged app will declare that multiple instances are prohibited, and the development
launcher will open the app normally instead of forcing a new process.

## Data Flow

1. Capture callbacks synchronously yield frames into one ordered stream.
2. One audio processor resamples, filters, analyzes, and appends every frame.
3. Release stops the audio input and drains the frame stream.
4. The orchestrator sends all processed samples in one Whisper request.
5. The final transcript pipeline repairs and formats that one complete result once.
6. Murmur inserts and stores only that result.

## Error Handling

An empty or failed full-recording decode fails the session instead of inserting partial
text. Cancellation checks remain after suspension points so stale sessions cannot insert.
No raw recording is retained unless the existing privacy setting explicitly enables it.

## Verification

- A recording containing speech, a long pause, and more speech produces exactly one
  transcription request containing the entire sample buffer.
- Quiet speech at the end is included because no tail gate can discard it.
- The final transcript pipeline is invoked only on the full-pass result.
- Existing ordered-frame and stop-race tests continue to pass.
- The built Info.plist prohibits multiple instances and the launcher does not use `open -n`.
- The complete Swift test suite and release build pass.
