package voice

import (
	"log"
	"os"

	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"

	"claude-voice-proxy/voice/stt"
)

// VoiceModels holds loaded Sherpa-ONNX model instances.
type VoiceModels struct {
	config  *VoiceConfig
	VAD     *sherpa.VoiceActivityDetector
	Engines []stt.Engine
	TTS     *sherpa.OfflineTts
	hasVAD  bool
	hasSTT  bool
	hasTTS  bool
}

// NewVoiceModels initialises voice models from config.
// Missing model files are logged as warnings; the pipeline degrades gracefully.
func NewVoiceModels(cfg *VoiceConfig) (*VoiceModels, error) {
	m := &VoiceModels{config: cfg}

	// ── VAD: Silero ──────────────────────────────────────────────────────────
	if _, err := os.Stat(cfg.VADModel); err == nil {
		vadCfg := &sherpa.VadModelConfig{
			SileroVad: sherpa.SileroVadModelConfig{
				Model:              cfg.VADModel,
				Threshold:          cfg.VADThreshold,
				MinSilenceDuration: float32(cfg.VADSilenceMs) / 1000.0,
				MinSpeechDuration:  0.25, // ignore noise bursts < 250ms
				WindowSize:         512, // 32ms @ 16kHz
				MaxSpeechDuration:  30.0,
			},
			SampleRate: 16000,
			NumThreads: 1,
			Provider:   "cpu",
			Debug:      0,
		}
		m.VAD = sherpa.NewVoiceActivityDetector(vadCfg, 60)
		if m.VAD != nil {
			m.hasVAD = true
			log.Printf("[Voice] VAD loaded: %s", cfg.VADModel)
		} else {
			log.Printf("[Voice] VAD init failed (model=%s)", cfg.VADModel)
		}
	} else {
		log.Printf("[Voice] VAD model not found: %s (run models/download.sh)", cfg.VADModel)
	}

	// ── STT: load all configured directories ────────────────────────────────
	for _, dir := range cfg.STTDirs {
		if dir == "" {
			continue
		}
		eng, err := stt.Load(dir, cfg.STTNumThreads)
		if err != nil {
			log.Printf("[Voice] STT skip %s: %v", dir, err)
			continue
		}
		m.Engines = append(m.Engines, eng)
		log.Printf("[Voice] STT loaded: %s", eng.Name())
	}
	m.hasSTT = len(m.Engines) > 0

	// ── TTS: Kokoro multi-lang ───────────────────────────────────────────────
	if _, err := os.Stat(cfg.TTSModel); err == nil {
		ttsCfg := &sherpa.OfflineTtsConfig{
			Model: sherpa.OfflineTtsModelConfig{
				Kokoro: sherpa.OfflineTtsKokoroModelConfig{
					Model:       cfg.TTSModel,
					Voices:      cfg.TTSVoices,
					Tokens:      cfg.TTSTokens,
					Lexicon:     cfg.TTSLexicon,
					DataDir:     cfg.TTSDataDir,
					LengthScale: 1.0,
				},
				NumThreads: cfg.TTSNumThreads,
				Debug:      0,
				Provider:   "cpu",
			},
			MaxNumSentences: 1,
		}
		m.TTS = sherpa.NewOfflineTts(ttsCfg)
		if m.TTS != nil {
			m.hasTTS = true
			log.Printf("[Voice] TTS loaded: %s (speakers=%d sampleRate=%d)",
				cfg.TTSModel, m.TTS.NumSpeakers(), m.TTS.SampleRate())
		} else {
			log.Printf("[Voice] TTS init failed (model=%s)", cfg.TTSModel)
		}
	} else {
		log.Printf("[Voice] TTS model not found: %s (run models/download.sh)", cfg.TTSModel)
	}

	log.Printf("[Voice] models ready (VAD=%v STT=%v TTS=%v)", m.hasVAD, m.hasSTT, m.hasTTS)
	return m, nil
}

// HasVAD reports whether the VAD model is loaded.
func (m *VoiceModels) HasVAD() bool { return m.hasVAD }

// HasSTT reports whether the STT model is loaded.
func (m *VoiceModels) HasSTT() bool { return m.hasSTT }

// HasTTS reports whether the TTS model is loaded.
func (m *VoiceModels) HasTTS() bool { return m.hasTTS }

// Capabilities returns the current capability set.
func (m *VoiceModels) Capabilities() Capabilities {
	return Capabilities{VAD: m.hasVAD, STT: m.hasSTT, TTS: m.hasTTS}
}

// Close releases all loaded model resources.
func (m *VoiceModels) Close() {
	if m.VAD != nil {
		sherpa.DeleteVoiceActivityDetector(m.VAD)
		m.VAD = nil
	}
	for _, e := range m.Engines {
		e.Close()
	}
	m.Engines = nil
	if m.TTS != nil {
		sherpa.DeleteOfflineTts(m.TTS)
		m.TTS = nil
	}
	log.Println("[Voice] models closed")
}

