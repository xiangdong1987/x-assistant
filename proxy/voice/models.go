package voice

import (
	"log"
	"os"
	"path/filepath"

	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"
)

// VoiceModels holds loaded Sherpa-ONNX model instances.
type VoiceModels struct {
	config     *VoiceConfig
	VAD        *sherpa.VoiceActivityDetector
	Recognizer *sherpa.OnlineRecognizer
	TTS        *sherpa.OfflineTts
	hasVAD     bool
	hasSTT     bool
	hasTTS     bool
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
				MinSpeechDuration:  0.1,
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

	// ── STT: Streaming Zipformer (Transducer) ────────────────────────────────
	encoderPath := filepath.Join(cfg.STTDir, "encoder.int8.onnx")
	decoderPath := filepath.Join(cfg.STTDir, "decoder.int8.onnx")
	joinerPath := filepath.Join(cfg.STTDir, "joiner.int8.onnx")
	tokensPath := filepath.Join(cfg.STTDir, "tokens.txt")

	if allExist(encoderPath, decoderPath, joinerPath, tokensPath) {
		recCfg := &sherpa.OnlineRecognizerConfig{
			FeatConfig: sherpa.FeatureConfig{
				SampleRate: 16000,
				FeatureDim: 80,
			},
			ModelConfig: sherpa.OnlineModelConfig{
				Transducer: sherpa.OnlineTransducerModelConfig{
					Encoder: encoderPath,
					Decoder: decoderPath,
					Joiner:  joinerPath,
				},
				Tokens:     tokensPath,
				NumThreads: cfg.STTNumThreads,
				Provider:   "cpu",
				Debug:      0,
				ModelType:  "zipformer",
			},
			DecodingMethod:          "greedy_search",
			EnableEndpoint:          1,
			Rule1MinTrailingSilence: 2.4,
			Rule2MinTrailingSilence: 1.2,
			Rule3MinUtteranceLength: 20,
		}
		m.Recognizer = sherpa.NewOnlineRecognizer(recCfg)
		if m.Recognizer != nil {
			m.hasSTT = true
			log.Printf("[Voice] STT loaded: %s", cfg.STTDir)
		} else {
			log.Printf("[Voice] STT init failed (dir=%s)", cfg.STTDir)
		}
	} else {
		log.Printf("[Voice] STT models not found in %s (run models/download.sh)", cfg.STTDir)
	}

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
	if m.Recognizer != nil {
		sherpa.DeleteOnlineRecognizer(m.Recognizer)
		m.Recognizer = nil
	}
	if m.TTS != nil {
		sherpa.DeleteOfflineTts(m.TTS)
		m.TTS = nil
	}
	log.Println("[Voice] models closed")
}

// allExist returns true if every path exists.
func allExist(paths ...string) bool {
	for _, p := range paths {
		if _, err := os.Stat(p); err != nil {
			return false
		}
	}
	return true
}
