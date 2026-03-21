package voice

import "encoding/json"

// VoiceMessage is the common envelope for all JSON control messages.
type VoiceMessage struct {
	Type    string          `json:"type"`
	ID      string          `json:"id,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// ── Client → Server ──────────────────────────────────────────────────────────

type VoiceStartPayload struct {
	SessionID  string `json:"session_id"`
	SampleRate int    `json:"sample_rate"` // client input sample rate (e.g. 16000)
	Language   string `json:"language"`    // "zh", "en", "auto"
	SpeakerID  int    `json:"speaker_id"`  // TTS speaker index
}

type VoiceStopPayload struct {
	SessionID string `json:"session_id"`
}

type VoiceCancelPayload struct {
	SessionID string `json:"session_id"`
}

type VoiceConfigPayload struct {
	SessionID    string  `json:"session_id"`
	VADThreshold float32 `json:"vad_threshold,omitempty"`
	VADSilenceMs int     `json:"vad_silence_ms,omitempty"`
	SpeakerID    int     `json:"speaker_id,omitempty"`
}

// ── Server → Client ──────────────────────────────────────────────────────────

type Capabilities struct {
	VAD bool `json:"vad"`
	STT bool `json:"stt"`
	TTS bool `json:"tts"`
}

type VoiceReadyPayload struct {
	SessionID    string       `json:"session_id"`
	Capabilities Capabilities `json:"capabilities"`
}

type VoiceVADStartPayload struct {
	SessionID   string `json:"session_id"`
	TimestampMs int64  `json:"timestamp_ms"`
}

type VoiceVADEndPayload struct {
	SessionID   string `json:"session_id"`
	TimestampMs int64  `json:"timestamp_ms"`
	DurationMs  int64  `json:"duration_ms"`
}

type VoiceTranscriptPayload struct {
	SessionID string `json:"session_id"`
	Text      string `json:"text"`
	IsFinal   bool   `json:"is_final"`
	Language  string `json:"language,omitempty"`
}

type VoiceAIStartPayload struct {
	SessionID  string `json:"session_id"`
	Transcript string `json:"transcript"`
}

type VoiceAIStreamPayload struct {
	SessionID string `json:"session_id"`
	Content   string `json:"content"`
}

type VoiceTTSStartPayload struct {
	SessionID  string `json:"session_id"`
	SampleRate int    `json:"sample_rate"`
}

type VoiceTTSEndPayload struct {
	SessionID  string `json:"session_id"`
	DurationMs int64  `json:"duration_ms"`
}

type VoiceAICompletePayload struct {
	SessionID string `json:"session_id"`
	Status    string `json:"status"` // success, error, cancelled
	Error     string `json:"error,omitempty"`
}

type VoiceErrorPayload struct {
	SessionID string `json:"session_id"`
	Code      string `json:"code"`
	Message   string `json:"message"`
}

// ── Helper constructors ───────────────────────────────────────────────────────

func newMsg(msgType string, payload interface{}) VoiceMessage {
	data, _ := json.Marshal(payload)
	return VoiceMessage{Type: msgType, Payload: json.RawMessage(data)}
}

func MsgReady(sessionID string, caps Capabilities) VoiceMessage {
	return newMsg("voice_ready", VoiceReadyPayload{SessionID: sessionID, Capabilities: caps})
}

func MsgVADStart(sessionID string, tsMs int64) VoiceMessage {
	return newMsg("voice_vad_start", VoiceVADStartPayload{SessionID: sessionID, TimestampMs: tsMs})
}

func MsgVADEnd(sessionID string, tsMs, durMs int64) VoiceMessage {
	return newMsg("voice_vad_end", VoiceVADEndPayload{SessionID: sessionID, TimestampMs: tsMs, DurationMs: durMs})
}

func MsgTranscript(sessionID, text string, isFinal bool) VoiceMessage {
	return newMsg("voice_transcript", VoiceTranscriptPayload{SessionID: sessionID, Text: text, IsFinal: isFinal})
}

func MsgAIStart(sessionID, transcript string) VoiceMessage {
	return newMsg("voice_ai_start", VoiceAIStartPayload{SessionID: sessionID, Transcript: transcript})
}

func MsgAIStream(sessionID, content string) VoiceMessage {
	return newMsg("voice_ai_stream", VoiceAIStreamPayload{SessionID: sessionID, Content: content})
}

func MsgTTSStart(sessionID string, sampleRate int) VoiceMessage {
	return newMsg("voice_tts_start", VoiceTTSStartPayload{SessionID: sessionID, SampleRate: sampleRate})
}

func MsgTTSEnd(sessionID string, durMs int64) VoiceMessage {
	return newMsg("voice_tts_end", VoiceTTSEndPayload{SessionID: sessionID, DurationMs: durMs})
}

func MsgAIComplete(sessionID, status, errMsg string) VoiceMessage {
	return newMsg("voice_ai_complete", VoiceAICompletePayload{SessionID: sessionID, Status: status, Error: errMsg})
}

func MsgError(sessionID, code, message string) VoiceMessage {
	return newMsg("voice_error", VoiceErrorPayload{SessionID: sessionID, Code: code, Message: message})
}
