package voice

import (
	"fmt"
	"path/filepath"
)

// VoiceConfig holds all configuration for the voice pipeline.
type VoiceConfig struct {
	Enabled bool

	ModelsDir string

	// VAD (Silero)
	VADModel     string
	VADThreshold float32
	VADSilenceMs int // milliseconds of silence to end an utterance

	// STT (Streaming Zipformer / Paraformer)
	STTDir        string
	STTNumThreads int

	// TTS (Kokoro)
	TTSModel       string
	TTSVoices      string
	TTSTokens      string
	TTSLexicon     string
	TTSDataDir     string // espeak-ng-data directory
	TTSNumThreads  int
	TTSSampleRate  int
	DefaultSpeaker int
}

// DefaultVoiceConfig returns a VoiceConfig with sensible defaults.
func DefaultVoiceConfig(modelsDir string) *VoiceConfig {
	return &VoiceConfig{
		Enabled:        false,
		ModelsDir:      modelsDir,
		VADModel:       filepath.Join(modelsDir, "vad", "silero_vad.onnx"),
		VADThreshold:   0.5,
		VADSilenceMs:   500,
		STTDir:         filepath.Join(modelsDir, "stt"),
		STTNumThreads:  2,
		TTSModel:       filepath.Join(modelsDir, "tts", "model.onnx"),
		TTSVoices:      filepath.Join(modelsDir, "tts", "voices.bin"),
		TTSTokens:      filepath.Join(modelsDir, "tts", "tokens.txt"),
		TTSLexicon:     filepath.Join(modelsDir, "tts", "lexicon.txt"),
		TTSDataDir:     filepath.Join(modelsDir, "tts", "espeak-ng-data"),
		TTSNumThreads:  2,
		TTSSampleRate:  24000,
		DefaultSpeaker: 0,
	}
}

// Validate checks that required fields are set when voice is enabled.
func (c *VoiceConfig) Validate() error {
	if !c.Enabled {
		return nil
	}
	if c.ModelsDir == "" {
		return fmt.Errorf("voice: models directory must be set")
	}
	return nil
}
