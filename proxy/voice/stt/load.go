package stt

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Load detects the model type in dir and returns the appropriate Engine.
//
// Detection order:
//  1. Read "type.txt" in dir for an explicit type declaration.
//  2. Heuristic: presence of encoder.int8.onnx + decoder.int8.onnx + joiner.int8.onnx → zipformer
//  3. Heuristic: presence of model.int8.onnx or model.onnx → paraformer
//  4. Heuristic: presence of encoder.onnx + decoder.onnx → whisper
func Load(dir string, threads int) (Engine, error) {
	modelType, err := detectModelType(dir)
	if err != nil {
		return nil, fmt.Errorf("stt: cannot detect model type in %s: %w", dir, err)
	}

	switch modelType {
	case "zipformer", "conformer", "lstm", "streaming-transducer":
		return newOnlineEngine(dir, threads)
	case "paraformer", "sense-voice", "whisper", "moonshine":
		return newOfflineEngine(dir, modelType, threads)
	default:
		return nil, fmt.Errorf("stt: unrecognised model type %q in %s", modelType, dir)
	}
}

func detectModelType(dir string) (string, error) {
	// 1. Explicit type.txt
	if t := readFileTrimmed(filepath.Join(dir, "type.txt"), ""); t != "" {
		return strings.ToLower(t), nil
	}

	// 2. Zipformer / Transducer heuristic
	if allExist(
		filepath.Join(dir, "encoder.int8.onnx"),
		filepath.Join(dir, "decoder.int8.onnx"),
		filepath.Join(dir, "joiner.int8.onnx"),
	) {
		return "zipformer", nil
	}

	// 3. Paraformer heuristic
	if anyExists(filepath.Join(dir, "model.int8.onnx"), filepath.Join(dir, "model.onnx")) {
		return "paraformer", nil
	}

	// 4. Whisper heuristic
	if allExist(filepath.Join(dir, "encoder.onnx"), filepath.Join(dir, "decoder.onnx")) {
		return "whisper", nil
	}

	return "", fmt.Errorf("cannot determine model type (add type.txt with content: zipformer|paraformer|whisper)")
}

// ── helpers ──────────────────────────────────────────────────────────────────

func allExist(paths ...string) bool {
	for _, p := range paths {
		if _, err := os.Stat(p); err != nil {
			return false
		}
	}
	return true
}

func anyExists(paths ...string) bool {
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return true
		}
	}
	return false
}

func firstExisting(paths ...string) string {
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func readFileTrimmed(path, fallback string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return fallback
	}
	return strings.TrimSpace(string(b))
}
