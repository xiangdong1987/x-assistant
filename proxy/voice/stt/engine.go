package stt

// Engine abstracts streaming and batch STT recognisers behind a single interface.
// vadProcessor calls AcceptChunk for every audio frame while speech is detected,
// then Finalize when VAD signals end-of-utterance, then Reset for the next sentence.
type Engine interface {
	// AcceptChunk feeds one PCM-float32 chunk.
	// Returns (partial, true) for streaming engines; ("", false) for batch engines.
	AcceptChunk(samples []float32) (partial string, streaming bool)

	// Finalize flushes buffered audio and returns the final transcript.
	Finalize() string

	// Reset clears internal state for the next utterance.
	Reset()

	// Name returns a human-readable label for logging (e.g. "zipformer@./models/stt").
	Name() string

	// Close releases model resources.
	Close()
}
