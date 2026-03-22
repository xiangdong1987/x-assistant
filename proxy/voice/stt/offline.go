package stt

import (
	"fmt"
	"path/filepath"

	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"
)

// OfflineEngine wraps a Sherpa-ONNX batch recogniser (Paraformer, Whisper, etc.).
// Audio samples are accumulated during speech; Finalize runs a single batch decode.
type OfflineEngine struct {
	rec       *sherpa.OfflineRecognizer
	buf       []float32
	name      string
	modelType string
}

func newOfflineEngine(dir string, modelType string, threads int) (*OfflineEngine, error) {
	tokensPath := filepath.Join(dir, "tokens.txt")

	var modelCfg sherpa.OfflineModelConfig

	switch modelType {
	case "paraformer":
		modelPath := firstExisting(
			filepath.Join(dir, "model.int8.onnx"),
			filepath.Join(dir, "model.onnx"),
		)
		if modelPath == "" {
			return nil, fmt.Errorf("stt: paraformer model not found in %s", dir)
		}
		modelCfg = sherpa.OfflineModelConfig{
			Paraformer: sherpa.OfflineParaformerModelConfig{
				Model: modelPath,
			},
			Tokens:     tokensPath,
			NumThreads: threads,
			Provider:   "cpu",
			Debug:      0,
			ModelType:  "paraformer",
		}

	case "sense-voice":
		modelPath := firstExisting(
			filepath.Join(dir, "model.int8.onnx"),
			filepath.Join(dir, "model.onnx"),
		)
		if modelPath == "" {
			return nil, fmt.Errorf("stt: sense-voice model not found in %s", dir)
		}
		language := readFileTrimmed(filepath.Join(dir, "language.txt"), "auto")
		modelCfg = sherpa.OfflineModelConfig{
			SenseVoice: sherpa.OfflineSenseVoiceModelConfig{
				Model:                       modelPath,
				Language:                    language,
				UseInverseTextNormalization: 1, // enables punctuation
			},
			Tokens:     tokensPath,
			NumThreads: threads,
			Provider:   "cpu",
			Debug:      0,
			ModelType:  "sense_voice",
		}

	case "whisper":
		encoderPath := filepath.Join(dir, "encoder.onnx")
		decoderPath := filepath.Join(dir, "decoder.onnx")
		language := readFileTrimmed(filepath.Join(dir, "language.txt"), "zh")
		modelCfg = sherpa.OfflineModelConfig{
			Whisper: sherpa.OfflineWhisperModelConfig{
				Encoder:  encoderPath,
				Decoder:  decoderPath,
				Language: language,
				Task:     "transcribe",
			},
			Tokens:     tokensPath,
			NumThreads: threads,
			Provider:   "cpu",
			Debug:      0,
			ModelType:  "whisper",
		}

	default:
		return nil, fmt.Errorf("stt: unknown offline model type %q in %s", modelType, dir)
	}

	cfg := &sherpa.OfflineRecognizerConfig{
		FeatConfig: sherpa.FeatureConfig{
			SampleRate: 16000,
			FeatureDim: 80,
		},
		ModelConfig: modelCfg,
	}

	rec := sherpa.NewOfflineRecognizer(cfg)
	if rec == nil {
		return nil, fmt.Errorf("stt: failed to init offline recognizer (%s) in %s", modelType, dir)
	}
	return &OfflineEngine{rec: rec, name: modelType + "@" + dir, modelType: modelType}, nil
}

func (e *OfflineEngine) AcceptChunk(samples []float32) (string, bool) {
	e.buf = append(e.buf, samples...)
	return "", false // batch: no streaming partial
}

func (e *OfflineEngine) Finalize() string {
	if len(e.buf) == 0 {
		return ""
	}
	stream := sherpa.NewOfflineStream(e.rec)
	defer sherpa.DeleteOfflineStream(stream)
	stream.AcceptWaveform(16000, e.buf)
	e.rec.Decode(stream)
	result := stream.GetResult()
	if result != nil {
		return result.Text
	}
	return ""
}

func (e *OfflineEngine) Reset() {
	e.buf = e.buf[:0]
}

func (e *OfflineEngine) Name() string { return e.name }

func (e *OfflineEngine) Close() {
	if e.rec != nil {
		sherpa.DeleteOfflineRecognizer(e.rec)
		e.rec = nil
	}
}
