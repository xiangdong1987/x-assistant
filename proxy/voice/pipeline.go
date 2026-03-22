package voice

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"

	"claude-voice-proxy/websocket"
)

// HubCallbackRegistrar is the subset of Hub methods needed for voice callback registration.
type HubCallbackRegistrar interface {
	RegisterDeviceCallback(deviceID string, fn func([]byte))
	UnregisterDeviceCallback(deviceID string)
}

// DeviceAwareTaskSender is the interface for sending tasks to the AI backend.
// Mirrors websocket.DeviceAwareTaskSender to avoid a circular import.
type DeviceAwareTaskSender interface {
	SendTaskToAgentForDevice(deviceID, commandID, prompt, skill, priority string) (string, error)
	SendChatAbortForDevice(deviceID, runID string) error
}

// Pipeline wires a VoiceSession to the AI backend via the Hub callback mechanism.
type Pipeline struct {
	session    *VoiceSession
	hub        HubCallbackRegistrar
	taskSender DeviceAwareTaskSender
	deviceID   string // "voice_<sessionID>"

	mu         sync.Mutex
	ttsStream  *TTSStreamer // active TTS streamer, nil when idle
}

// NewPipeline creates and registers the AI response pipeline for a voice session.
func NewPipeline(session *VoiceSession, hub HubCallbackRegistrar, taskSender DeviceAwareTaskSender) *Pipeline {
	p := &Pipeline{
		session:    session,
		hub:        hub,
		taskSender: taskSender,
		deviceID:   fmt.Sprintf("voice_%s", session.sessionID),
	}
	hub.RegisterDeviceCallback(p.deviceID, p.onHubMessage)
	return p
}

// Close unregisters the Hub callback.
func (p *Pipeline) Close() {
	p.hub.UnregisterDeviceCallback(p.deviceID)
}

// ProcessTranscript sends transcribed text to the AI backend.
func (p *Pipeline) ProcessTranscript(text string) {
	if p.taskSender == nil {
		log.Printf("[Voice:%s] no AI backend configured", p.session.sessionID)
		p.session.SendJSON(MsgAIComplete(p.session.sessionID, "error", "AI backend not connected"))
		return
	}

	p.session.SendJSON(MsgAIStart(p.session.sessionID, text))

	// Prepare a fresh TTS streamer for this turn
	p.mu.Lock()
	if p.session.models.TTS != nil {
		p.ttsStream = NewTTSStreamer(p.session.models.TTS, p.session, p.session.models.config.DefaultSpeaker)
	}
	p.mu.Unlock()

	cmdID := fmt.Sprintf("voice_%s", p.session.sessionID)
	if _, err := p.taskSender.SendTaskToAgentForDevice(p.deviceID, cmdID, text, "", "p1"); err != nil {
		log.Printf("[Voice:%s] AI send error: %v", p.session.sessionID, err)
		p.mu.Lock()
		p.ttsStream = nil
		p.mu.Unlock()
		p.session.SendJSON(MsgAIComplete(p.session.sessionID, "error", err.Error()))
	}
}

// CancelCurrent aborts the in-flight AI request and stops TTS.
func (p *Pipeline) CancelCurrent() {
	p.mu.Lock()
	p.ttsStream = nil
	p.mu.Unlock()

	if p.taskSender == nil {
		return
	}
	cmdID := fmt.Sprintf("voice_%s", p.session.sessionID)
	if err := p.taskSender.SendChatAbortForDevice(p.deviceID, cmdID); err != nil {
		log.Printf("[Voice:%s] cancel error: %v", p.session.sessionID, err)
	}
	p.session.SendJSON(MsgAIComplete(p.session.sessionID, "cancelled", ""))
}

// onHubMessage is called by Hub when a message is targeted at this voice deviceID.
// Parses stream/complete messages, forwards AI text, and drives TTS synthesis.
func (p *Pipeline) onHubMessage(data []byte) {
	var msg struct {
		Type    string          `json:"type"`
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(data, &msg); err != nil {
		return
	}

	switch msg.Type {
	case "stream":
		var payload websocket.StreamPayload
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			return
		}
		// Forward text to client
		p.session.SendJSON(MsgAIStream(p.session.sessionID, payload.Content))

		// Feed text to TTS streamer (sentence-chunked synthesis)
		p.mu.Lock()
		ts := p.ttsStream
		p.mu.Unlock()
		if ts != nil {
			ts.Write(payload.Content)
		}

	case "complete":
		var payload websocket.CompletePayload
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			return
		}

		// Flush remaining TTS text and send end marker
		p.mu.Lock()
		ts := p.ttsStream
		p.ttsStream = nil
		p.mu.Unlock()

		if ts != nil {
			ts.Flush()
			ts.Finish()
		}

		p.session.SendJSON(MsgAIComplete(p.session.sessionID, payload.Status, payload.Error))
		log.Printf("[Voice:%s] turn complete: status=%s", p.session.sessionID, payload.Status)
	}
}
