package stt

import (
	"fmt"
	"path/filepath"

	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"
)

// OnlineEngine wraps a Sherpa-ONNX streaming transducer (e.g. Zipformer).
type OnlineEngine struct {
	rec    *sherpa.OnlineRecognizer
	stream *sherpa.OnlineStream
	name   string
	last   string // last partial text, to avoid duplicate events
}

func newOnlineEngine(dir string, threads int) (*OnlineEngine, error) {
	encoderPath := filepath.Join(dir, "encoder.int8.onnx")
	decoderPath := filepath.Join(dir, "decoder.int8.onnx")
	joinerPath  := filepath.Join(dir, "joiner.int8.onnx")
	tokensPath  := filepath.Join(dir, "tokens.txt")

	cfg := &sherpa.OnlineRecognizerConfig{
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
			NumThreads: threads,
			Provider:   "cpu",
			Debug:      0,
			ModelType:  "zipformer",
		},
		DecodingMethod:          "modified_beam_search",
		MaxActivePaths:          4,
		EnableEndpoint:          1,
		Rule1MinTrailingSilence: 2.0,
		Rule2MinTrailingSilence: 1.0,
		Rule3MinUtteranceLength: 20,
	}

	rec := sherpa.NewOnlineRecognizer(cfg)
	if rec == nil {
		return nil, fmt.Errorf("stt: failed to init online recognizer in %s", dir)
	}
	e := &OnlineEngine{rec: rec, name: "zipformer@" + dir}
	e.stream = sherpa.NewOnlineStream(rec)
	return e, nil
}

func (e *OnlineEngine) AcceptChunk(samples []float32) (string, bool) {
	e.stream.AcceptWaveform(16000, samples)
	for e.rec.IsReady(e.stream) {
		e.rec.Decode(e.stream)
	}
	result := e.rec.GetResult(e.stream)
	if result != nil && result.Text != "" && result.Text != e.last {
		e.last = result.Text
		return result.Text, true
	}
	// Handle mid-utterance endpoint
	if e.rec.IsEndpoint(e.stream) && e.last != "" {
		e.rec.Reset(e.stream)
	}
	return "", true // streaming=true so caller knows partial display is supported
}

func (e *OnlineEngine) Finalize() string {
	e.stream.InputFinished()
	for e.rec.IsReady(e.stream) {
		e.rec.Decode(e.stream)
	}
	result := e.rec.GetResult(e.stream)
	if result != nil {
		return result.Text
	}
	return e.last
}

func (e *OnlineEngine) Reset() {
	sherpa.DeleteOnlineStream(e.stream)
	e.stream = sherpa.NewOnlineStream(e.rec)
	e.last = ""
}

func (e *OnlineEngine) Name() string { return e.name }

func (e *OnlineEngine) Close() {
	if e.stream != nil {
		sherpa.DeleteOnlineStream(e.stream)
		e.stream = nil
	}
	if e.rec != nil {
		sherpa.DeleteOnlineRecognizer(e.rec)
		e.rec = nil
	}
}
