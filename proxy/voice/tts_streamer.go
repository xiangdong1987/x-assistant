package voice

import (
	"encoding/binary"
	"log"
	"math"
	"strings"
	"time"

	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"
)

// chunkDurationMs is the size of each PCM16 audio chunk sent to the client.
const chunkDurationMs = 20 // 20ms per frame

// TTSStreamer accumulates AI text deltas, detects sentence boundaries, and
// synthesises + streams audio chunks as each sentence completes.
type TTSStreamer struct {
	tts       *sherpa.OfflineTts
	session   *VoiceSession
	speakerID int
	buf       strings.Builder // accumulated text waiting for sentence boundary
	started   bool
	startedAt time.Time
	totalSamples int
}

// NewTTSStreamer creates a streamer ready to accept text deltas.
func NewTTSStreamer(tts *sherpa.OfflineTts, session *VoiceSession, speakerID int) *TTSStreamer {
	return &TTSStreamer{
		tts:       tts,
		session:   session,
		speakerID: speakerID,
	}
}

// Write appends a text delta and synthesises any complete sentences immediately.
func (t *TTSStreamer) Write(delta string) {
	if t.tts == nil || delta == "" {
		return
	}
	t.buf.WriteString(delta)
	t.synthesizePending(false)
}

// Flush synthesises any remaining buffered text after the AI stream ends.
func (t *TTSStreamer) Flush() {
	if t.tts == nil {
		return
	}
	t.synthesizePending(true)
}

// synthesizePending scans the buffer for sentence boundaries and synthesises each one.
// If force is true, synthesises whatever remains even without a boundary.
func (t *TTSStreamer) synthesizePending(force bool) {
	for {
		text := t.buf.String()
		if text == "" {
			return
		}

		idx := findSentenceBoundary(text)
		if idx < 0 {
			if !force {
				return
			}
			// Force: synthesise everything remaining
			t.buf.Reset()
			t.synthesize(strings.TrimSpace(text))
			return
		}

		sentence := strings.TrimSpace(text[:idx+1])
		rest := text[idx+1:]
		t.buf.Reset()
		t.buf.WriteString(rest)

		if sentence != "" {
			t.synthesize(sentence)
		}
	}
}

// synthesize calls TTS Generate and streams the result as binary PCM16 frames.
func (t *TTSStreamer) synthesize(text string) {
	if text == "" {
		return
	}
	log.Printf("[Voice:%s] TTS synthesize: %q", t.session.sessionID, truncate(text, 50))

	audio := t.tts.Generate(text, t.speakerID, 1.0)
	if audio == nil || len(audio.Samples) == 0 {
		log.Printf("[Voice:%s] TTS: no audio generated for %q", t.session.sessionID, truncate(text, 30))
		return
	}

	if !t.started {
		t.started = true
		t.startedAt = time.Now()
		t.session.SendJSON(MsgTTSStart(t.session.sessionID, audio.SampleRate))
	}

	t.totalSamples += len(audio.Samples)

	// Chunk into frames and send as binary WebSocket messages
	samplesPerChunk := audio.SampleRate * chunkDurationMs / 1000
	samples := audio.Samples
	for len(samples) > 0 {
		n := samplesPerChunk
		if n > len(samples) {
			n = len(samples)
		}
		pcm16 := float32ToPCM16(samples[:n])
		t.session.SendBinary(pcm16)
		samples = samples[n:]
	}
}

// Finish sends voice_tts_end if any audio was sent.
func (t *TTSStreamer) Finish() {
	if !t.started {
		return
	}
	// Estimate duration from total samples (using TTS sample rate, approximated)
	sampleRate := 24000
	if t.tts != nil {
		sampleRate = t.tts.SampleRate()
	}
	durMs := int64(t.totalSamples) * 1000 / int64(sampleRate)
	t.session.SendJSON(MsgTTSEnd(t.session.sessionID, durMs))
	log.Printf("[Voice:%s] TTS complete: %d samples (%dms)", t.session.sessionID, t.totalSamples, durMs)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// findSentenceBoundary returns the byte index of the first sentence-ending punctuation,
// requiring at least a minimum number of runes before the boundary to avoid
// synthesising single characters.
func findSentenceBoundary(s string) int {
	const minRunes = 5
	runeCount := 0
	for i, r := range s {
		runeCount++
		if runeCount < minRunes {
			continue
		}
		switch r {
		case '.', '!', '?', '。', '！', '？', '…', '\n':
			// Ensure the boundary is not at a decimal number (e.g. "3.14")
			if r == '.' && i > 0 {
				prev := s[i-1]
				if prev >= '0' && prev <= '9' {
					continue
				}
			}
			return i
		}
	}
	return -1
}

// float32ToPCM16 converts float32 samples [-1,1] to PCM16 LE bytes.
func float32ToPCM16(samples []float32) []byte {
	buf := make([]byte, len(samples)*2)
	for i, s := range samples {
		// Clamp to [-1, 1]
		if s > 1.0 {
			s = 1.0
		} else if s < -1.0 {
			s = -1.0
		}
		v := int16(s * math.MaxInt16)
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(v))
	}
	return buf
}

// truncate shortens a string to maxRunes runes for logging.
func truncate(s string, maxRunes int) string {
	count := 0
	for i := range s {
		count++
		if count > maxRunes {
			return s[:i] + "…"
		}
	}
	return s
}
