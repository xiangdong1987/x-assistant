package server

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"runtime"

	"claude-voice-proxy/auth"
	"claude-voice-proxy/voice"
)

// handleVoiceWebSocket upgrades the connection to the voice WebSocket pipeline.
// Uses the same JWT token validation pattern as handleWebSocket.
func (s *Server) handleVoiceWebSocket(w http.ResponseWriter, r *http.Request) {
	if s.voiceModels == nil {
		http.Error(w, "voice pipeline not enabled", http.StatusServiceUnavailable)
		return
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, "Unauthorized: no token", http.StatusUnauthorized)
		return
	}
	if _, err := auth.ValidateToken(token); err != nil {
		http.Error(w, "Unauthorized: invalid token", http.StatusUnauthorized)
		return
	}

	// openclawBridge implements DeviceAwareTaskSender; pass nil explicitly to avoid
	// the Go nil-interface trap (typed nil != untyped nil).
	var taskSender voice.DeviceAwareTaskSender
	if s.openclawBridge != nil {
		taskSender = s.openclawBridge
	}
	voice.ServeVoiceWs(s.voiceModels, s.hub, taskSender, w, r)
}

// handleVoiceTestPage serves the browser-based voice test page.
func (s *Server) handleVoiceTestPage(w http.ResponseWriter, r *http.Request) {
	// Locate the HTML file relative to this source file at build time,
	// falling back to a path relative to the working directory.
	_, thisFile, _, _ := runtime.Caller(0)
	candidates := []string{
		filepath.Join(filepath.Dir(filepath.Dir(thisFile)), "tools", "voice-test", "index.html"),
		"tools/voice-test/index.html",
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			http.ServeFile(w, r, p)
			return
		}
	}
	http.Error(w, "voice test page not found", http.StatusNotFound)
}

// handleVoiceStatus returns the current voice pipeline status as JSON.
func (s *Server) handleVoiceStatus(w http.ResponseWriter, _ *http.Request) {
	type statusResp struct {
		Enabled      bool               `json:"enabled"`
		Capabilities voice.Capabilities `json:"capabilities"`
	}

	resp := statusResp{Enabled: s.voiceModels != nil}
	if s.voiceModels != nil {
		resp.Capabilities = s.voiceModels.Capabilities()
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
