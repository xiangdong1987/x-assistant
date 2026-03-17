package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"
)

// WebSocketMessage represents a message from WebSocket client
type WebSocketMessage struct {
	Type    string          `json:"type"`
	ID      string          `json:"id"`
	Payload json.RawMessage `json:"payload"`
}

// CommandPayload represents a command payload from WebSocket
type CommandPayload struct {
	Text       string            `json:"text"`
	WorkingDir string            `json:"working_dir,omitempty"`
	Options    map[string]string `json:"options,omitempty"`
}

// StreamPayload represents a stream payload to WebSocket
type StreamPayload struct {
	CommandID   string `json:"command_id"`
	Content     string `json:"content"`
	ContentType string `json:"content_type"` // text, code, tool_use, error
}

// CompletePayload represents a completion payload to WebSocket
type CompletePayload struct {
	CommandID string                 `json:"command_id"`
	Status    string                 `json:"status"` // success, error, cancelled
	Result    map[string]interface{} `json:"result,omitempty"`
	Error     string                 `json:"error,omitempty"`
}

// Handler handles WebSocket messages and forwards them to MCP
type Handler struct {
	clientFactory *ClientFactory
	streamCallbacks map[string]func(content string, contentType string)
	mu             sync.RWMutex
}

// NewHandler creates a new handler
func NewHandler(config *Config) *Handler {
	factory := NewClientFactory(config)
	return &Handler{
		clientFactory:   factory,
		streamCallbacks: make(map[string]func(content string, contentType string)),
	}
}

// HandleMessage handles a WebSocket message
func (h *Handler) HandleMessage(deviceID string, msg *WebSocketMessage) error {
	switch msg.Type {
	case "command":
		return h.handleCommand(deviceID, msg)
	case "cancel":
		return h.handleCancel(deviceID, msg)
	case "ping":
		return h.handlePing(deviceID, msg)
	default:
		return fmt.Errorf("unknown message type: %s", msg.Type)
	}
}

// handleCommand handles a command message
func (h *Handler) handleCommand(deviceID string, msg *WebSocketMessage) error {
	// Parse command payload
	var payload CommandPayload
	if err := json.Unmarshal(msg.Payload, &payload); err != nil {
		return fmt.Errorf("failed to parse command payload: %w", err)
	}
	
	// Get or create client
	client, err := h.clientFactory.GetOrCreateClient(deviceID)
	if err != nil {
		return fmt.Errorf("failed to get cursor client: %w", err)
	}
	
	// Create stream callback
	streamCallback := func(content string, contentType string) {
		h.sendStream(msg.ID, content, contentType)
	}
	
	h.mu.Lock()
	h.streamCallbacks[msg.ID] = streamCallback
	h.mu.Unlock()
	
	// Execute command in goroutine
	go h.executeCommandAsync(deviceID, client, msg.ID, payload.Text, payload.WorkingDir, streamCallback)
	
	return nil
}

// executeCommandAsync executes a command asynchronously
func (h *Handler) executeCommandAsync(deviceID string, client *CursorClient, commandID, text, workingDir string, streamCallback func(content string, contentType string)) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	
	// Send initial stream message
	streamCallback("Processing command...", "text")
	
	var result map[string]interface{}
	var finalError error
	
	// Execute command based on content
	if workingDir != "" {
		// This is likely a shell command
		response, err := client.ExecuteCommand(ctx, text, workingDir)
		if err != nil {
			finalError = err
		} else {
			streamCallback(response, "text")
			result = map[string]interface{}{
				"response": response,
			}
		}
	} else {
		// This is a general message to Cursor
		response, err := client.SendMessage(ctx, text)
		if err != nil {
			finalError = err
		} else {
			streamCallback(response, "text")
			result = map[string]interface{}{
				"response": response,
			}
		}
	}
	
	// Send completion message
	h.sendComplete(commandID, result, finalError)
	
	// Clean up stream callback
	h.mu.Lock()
	delete(h.streamCallbacks, commandID)
	h.mu.Unlock()
}

// handleCancel handles a cancel message
func (h *Handler) handleCancel(deviceID string, msg *WebSocketMessage) error {
	var payload struct {
		CommandID string `json:"command_id"`
	}
	if err := json.Unmarshal(msg.Payload, &payload); err != nil {
		return fmt.Errorf("failed to parse cancel payload: %w", err)
	}
	
	// Remove stream callback
	h.mu.Lock()
	delete(h.streamCallbacks, payload.CommandID)
	h.mu.Unlock()
	
	// Send cancellation complete
	h.sendComplete(payload.CommandID, nil, fmt.Errorf("command cancelled"))
	
	return nil
}

// handlePing handles a ping message
func (h *Handler) handlePing(deviceID string, msg *WebSocketMessage) error {
	// Just acknowledge ping
	h.sendPong(msg.ID)
	return nil
}

// sendStream sends a stream message
func (h *Handler) sendStream(commandID, content, contentType string) {
	// TODO: Send to WebSocket client
	// payload := StreamPayload{
	// 	CommandID:   commandID,
	// 	Content:     content,
	// 	ContentType: contentType,
	// }
	log.Printf("Stream [%s]: %s", contentType, content)
}

// sendComplete sends a completion message
func (h *Handler) sendComplete(commandID string, result map[string]interface{}, err error) {
	// TODO: Send to WebSocket client
	// payload := CompletePayload{
	// 	CommandID: commandID,
	// }
	
	status := "success"
	errorMsg := ""
	if err != nil {
		status = "error"
		errorMsg = err.Error()
	}
	
	log.Printf("Complete [%s]: %v", status, errorMsg)
}

// sendPong sends a pong response
func (h *Handler) sendPong(id string) {
	// TODO: Send pong to WebSocket client
	log.Printf("Pong for: %s", id)
}

// Cleanup cleans up the handler
func (h *Handler) Cleanup() {
	h.clientFactory.Cleanup()
}

// WebSocketHandlerInterface defines the interface for WebSocket handlers
type WebSocketHandlerInterface interface {
	HandleMessage(deviceID string, msg []byte) error
	Cleanup()
}

// WebSocketHandler implements WebSocketHandlerInterface
type WebSocketHandler struct {
	handler *Handler
}

// NewWebSocketHandler creates a new WebSocket handler
func NewWebSocketHandler(config *Config) *WebSocketHandler {
	return &WebSocketHandler{
		handler: NewHandler(config),
	}
}

// HandleMessage handles a WebSocket message
func (w *WebSocketHandler) HandleMessage(deviceID string, msg []byte) error {
	var wsMsg WebSocketMessage
	if err := json.Unmarshal(msg, &wsMsg); err != nil {
		return fmt.Errorf("failed to parse WebSocket message: %w", err)
	}
	
	return w.handler.HandleMessage(deviceID, &wsMsg)
}

// Cleanup cleans up the handler
func (w *WebSocketHandler) Cleanup() {
	w.handler.Cleanup()
}