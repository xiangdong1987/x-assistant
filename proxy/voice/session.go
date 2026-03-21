package voice

import (
	"encoding/binary"
	"encoding/json"
	"log"
	"math"
	"time"

	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"
	"github.com/gorilla/websocket"
)

const (
	voiceWriteWait  = 10 * time.Second
	voicePongWait   = 60 * time.Second
	voicePingPeriod = (voicePongWait * 9) / 10
	voiceMaxMsgSize = 2 * 1024 * 1024 // 2MB

	// VAD window size must match model config (512 samples @ 16kHz = 32ms)
	vadWindowSamples = 512
	sttSampleRate    = 16000
)

// sendItem wraps a WebSocket frame to be written by writePump.
type sendItem struct {
	msgType int    // websocket.TextMessage or websocket.BinaryMessage
	data    []byte
}

// SpeechSegment carries a finalized utterance from vadProcessor to aiTtsWorker.
type SpeechSegment struct {
	Text       string
	DurationMs int64
}

// VoiceSession represents a single /voice/ws connection.
type VoiceSession struct {
	conn       *websocket.Conn
	models     *VoiceModels
	sessionID  string
	pipeline   *Pipeline            // set after voice_start, used by aiTtsWorker
	hub        HubCallbackRegistrar // injected by handler
	taskSender DeviceAwareTaskSender // injected by handler

	// channels
	send     chan sendItem      // writePump reads from here
	audioIn  chan []byte        // binary PCM16 frames from client
	ctrl     chan VoiceMessage  // JSON control messages
	speech   chan SpeechSegment // vadProcessor → aiTtsWorker
	cancelCh chan struct{}      // closed when readPump exits
}

// newVoiceSession creates a session for an established WebSocket connection.
func newVoiceSession(conn *websocket.Conn, models *VoiceModels) *VoiceSession {
	return &VoiceSession{
		conn:     conn,
		models:   models,
		send:     make(chan sendItem, 256),
		audioIn:  make(chan []byte, 64),
		ctrl:     make(chan VoiceMessage, 16),
		speech:   make(chan SpeechSegment, 4),
		cancelCh: make(chan struct{}),
	}
}

// ── Public send helpers ───────────────────────────────────────────────────────

func (s *VoiceSession) SendJSON(msg VoiceMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	s.safeSend(sendItem{msgType: websocket.TextMessage, data: data})
}

func (s *VoiceSession) SendBinary(data []byte) {
	cp := make([]byte, len(data))
	copy(cp, data)
	s.safeSend(sendItem{msgType: websocket.BinaryMessage, data: cp})
}

// safeSend writes to the send channel, silently discarding if the channel is
// closed (session already torn down) or the buffer is full.
func (s *VoiceSession) safeSend(item sendItem) {
	defer func() { recover() }() // recover from send-on-closed-channel panic
	select {
	case s.send <- item:
	default:
		log.Printf("[Voice:%s] send buffer full, dropping frame type=%d", s.sessionID, item.msgType)
	}
}

// ── writePump ────────────────────────────────────────────────────────────────

func (s *VoiceSession) writePump() {
	ticker := time.NewTicker(voicePingPeriod)
	defer func() {
		ticker.Stop()
		s.conn.Close()
	}()

	for {
		select {
		case item, ok := <-s.send:
			s.conn.SetWriteDeadline(time.Now().Add(voiceWriteWait))
			if !ok {
				s.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := s.conn.WriteMessage(item.msgType, item.data); err != nil {
				return
			}

		case <-ticker.C:
			s.conn.SetWriteDeadline(time.Now().Add(voiceWriteWait))
			if err := s.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ── readPump ─────────────────────────────────────────────────────────────────

func (s *VoiceSession) readPump() {
	defer func() {
		close(s.cancelCh)
		close(s.send)
		s.conn.Close()
	}()

	s.conn.SetReadLimit(voiceMaxMsgSize)
	s.conn.SetReadDeadline(time.Now().Add(voicePongWait))
	s.conn.SetPongHandler(func(string) error {
		s.conn.SetReadDeadline(time.Now().Add(voicePongWait))
		return nil
	})

	for {
		msgType, data, err := s.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[Voice:%s] read error: %v", s.sessionID, err)
			}
			return
		}

		switch msgType {
		case websocket.BinaryMessage:
			select {
			case s.audioIn <- data:
			default:
				log.Printf("[Voice:%s] audioIn full, dropping %d bytes", s.sessionID, len(data))
			}

		case websocket.TextMessage:
			var msg VoiceMessage
			if err := json.Unmarshal(data, &msg); err != nil {
				log.Printf("[Voice:%s] invalid JSON: %v", s.sessionID, err)
				continue
			}
			s.handleCtrlMessage(msg)
		}
	}
}

// ── Control message handler ──────────────────────────────────────────────────

func (s *VoiceSession) handleCtrlMessage(msg VoiceMessage) {
	switch msg.Type {
	case "voice_start":
		var p VoiceStartPayload
		if err := json.Unmarshal(msg.Payload, &p); err != nil {
			s.SendJSON(MsgError(s.sessionID, "bad_payload", "invalid voice_start payload"))
			return
		}
		s.sessionID = p.SessionID
		log.Printf("[Voice:%s] session started (lang=%s speaker=%d)", s.sessionID, p.Language, p.SpeakerID)
		// Build AI pipeline once we have a sessionID
		if s.hub != nil && s.taskSender != nil {
			s.pipeline = NewPipeline(s, s.hub, s.taskSender)
		}
		s.SendJSON(MsgReady(s.sessionID, s.models.Capabilities()))

	case "voice_stop":
		log.Printf("[Voice:%s] session stopped by client", s.sessionID)
		s.conn.Close()

	case "voice_cancel":
		log.Printf("[Voice:%s] cancel requested", s.sessionID)
		if s.pipeline != nil {
			s.pipeline.CancelCurrent()
		}

	case "voice_config":
		log.Printf("[Voice:%s] config update received", s.sessionID)

	case "ping":
		s.SendJSON(VoiceMessage{Type: "pong", ID: msg.ID})

	default:
		log.Printf("[Voice:%s] unknown message type: %s", s.sessionID, msg.Type)
	}
}

// ── VAD + STT processor goroutine ────────────────────────────────────────────

// vadProcessor continuously reads PCM16 frames from audioIn, runs Silero VAD
// and (if available) streaming STT. It emits voice_vad_start/end events and
// voice_transcript (partial + final) messages, and pushes finalized SpeechSegments
// to the speech channel for AI processing.
func (s *VoiceSession) vadProcessor() {
	vad := s.models.VAD
	rec := s.models.Recognizer

	if vad == nil {
		// Drain audioIn to prevent sender blocking
		for {
			select {
			case <-s.cancelCh:
				return
			case <-s.audioIn:
			}
		}
	}

	var (
		buf         []float32
		speaking    bool
		speechStart time.Time
		sttStream   *sherpa.OnlineStream
		lastText    string
	)

	finalizeSpeech := func() {
		if !speaking {
			return
		}
		speaking = false
		durMs := time.Since(speechStart).Milliseconds()
		s.SendJSON(MsgVADEnd(s.sessionID, time.Now().UnixMilli(), durMs))

		finalText := lastText
		if rec != nil && sttStream != nil {
			sttStream.InputFinished()
			// Decode any remaining frames
			for rec.IsReady(sttStream) {
				rec.Decode(sttStream)
			}
			result := rec.GetResult(sttStream)
			if result != nil && result.Text != "" {
				finalText = result.Text
			}
			sherpa.DeleteOnlineStream(sttStream)
			sttStream = nil
			lastText = ""
		}

		if finalText != "" {
			s.SendJSON(MsgTranscript(s.sessionID, finalText, true))
			log.Printf("[Voice:%s] transcript (final): %q", s.sessionID, finalText)
			select {
			case s.speech <- SpeechSegment{Text: finalText, DurationMs: durMs}:
			default:
				log.Printf("[Voice:%s] speech channel full, dropping segment", s.sessionID)
			}
		}
	}

	for {
		select {
		case <-s.cancelCh:
			finalizeSpeech()
			return

		case pcm16, ok := <-s.audioIn:
			if !ok {
				return
			}
			samples := pcm16ToFloat32(pcm16)
			buf = append(buf, samples...)

			// Feed VAD in vadWindowSamples-sized chunks
			for len(buf) >= vadWindowSamples {
				chunk := buf[:vadWindowSamples]
				buf = buf[vadWindowSamples:]

				vad.AcceptWaveform(chunk)

				isSpeaking := vad.IsSpeech()

				// Detect speech onset
				if isSpeaking && !speaking {
					speaking = true
					speechStart = time.Now()
					lastText = ""
					s.SendJSON(MsgVADStart(s.sessionID, speechStart.UnixMilli()))
					log.Printf("[Voice:%s] VAD: speech start", s.sessionID)

					if rec != nil {
						sttStream = sherpa.NewOnlineStream(rec)
					}
				}

				// Feed audio to STT while speaking
				if speaking && rec != nil && sttStream != nil {
					sttStream.AcceptWaveform(sttSampleRate, chunk)

					// Decode and emit partial transcript
					for rec.IsReady(sttStream) {
						rec.Decode(sttStream)
					}
					if result := rec.GetResult(sttStream); result != nil && result.Text != "" && result.Text != lastText {
						lastText = result.Text
						s.SendJSON(MsgTranscript(s.sessionID, lastText, false))
					}

					// On endpoint, reset stream and keep going (mid-utterance endpoint)
					if rec.IsEndpoint(sttStream) && lastText != "" {
						rec.Reset(sttStream)
					}
				}

				// Detect speech end
				if !isSpeaking && speaking {
					finalizeSpeech()
				}
			}

			// Drain completed VAD segments (not used for STT here, already handled above)
			for !vad.IsEmpty() {
				vad.Pop()
			}
		}
	}
}

// ── aiTtsWorker ──────────────────────────────────────────────────────────────

func (s *VoiceSession) aiTtsWorker() {
	for {
		select {
		case <-s.cancelCh:
			if s.pipeline != nil {
				s.pipeline.Close()
			}
			return
		case seg, ok := <-s.speech:
			if !ok {
				return
			}
			if s.pipeline == nil {
				log.Printf("[Voice:%s] no pipeline, dropping segment: %q", s.sessionID, seg.Text)
				continue
			}
			// Send transcript to AI backend; response comes back via Hub callback → pipeline
			s.pipeline.ProcessTranscript(seg.Text)
			// TODO Phase 6: TTS will be triggered by voice_ai_complete in pipeline
		}
	}
}

// ── Audio format helpers ──────────────────────────────────────────────────────

// pcm16ToFloat32 converts PCM16 little-endian bytes to float32 in [-1, 1].
func pcm16ToFloat32(b []byte) []float32 {
	n := len(b) / 2
	out := make([]float32, n)
	for i := range out {
		sample := int16(binary.LittleEndian.Uint16(b[i*2:]))
		out[i] = float32(sample) / math.MaxInt16
	}
	return out
}
