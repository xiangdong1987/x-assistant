package websocket

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"claude-voice-proxy/claude"
	"claude-voice-proxy/mcp"

	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 512 * 1024 // 512KB
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for local network
	},
}

// TaskSender defines an interface for sending tasks to an agent
type TaskSender interface {
	SendTaskToAgent(prompt, skill, priority string) (string, error)
	SendChatHistory(limit int) error
	SendChatAbort(runID string) error
}

// DeviceAwareTaskSender extends TaskSender with device-scoped sends for thread isolation
type DeviceAwareTaskSender interface {
	TaskSender
	SendTaskToAgentForDevice(deviceID, commandID, prompt, skill, priority string) (string, error)
	SendChatHistoryForDevice(deviceID string, limit int) error
	SendChatAbortForDevice(deviceID, runID string) error
}

// Client represents a WebSocket client connection
type Client struct {
	hub        *Hub
	conn       *websocket.Conn
	send       chan []byte
	deviceID   string
	workDir    string
	executor   *claude.Executor
	mcpConfig  *mcp.Config
	mcpHandler *mcp.WebSocketHandler
	taskSender TaskSender
}

// Message types
type WSMessage struct {
	Type    string          `json:"type"`
	ID      string          `json:"id"`
	Payload json.RawMessage `json:"payload"`
}

type CommandPayload struct {
	Text       string            `json:"text"`
	WorkingDir string            `json:"working_dir,omitempty"`
	Skill      string            `json:"skill,omitempty"`
	Options    map[string]string `json:"options,omitempty"`
}

type StreamPayload struct {
	CommandID   string `json:"command_id"`
	Content     string `json:"content"`
	ContentType string `json:"content_type"` // text, code, tool_use
}

type CompletePayload struct {
	CommandID string                 `json:"command_id"`
	Status    string                 `json:"status"` // success, error, cancelled
	Result    map[string]interface{} `json:"result,omitempty"`
	Error     string                 `json:"error,omitempty"`
}

// ServeWs handles WebSocket requests from clients
func ServeWs(hub *Hub, w http.ResponseWriter, r *http.Request, deviceID, workDir string, mcpConfig *mcp.Config, taskSender TaskSender) {
	log.Printf("Upgrading WebSocket connection for device: %s", deviceID)

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error for %s: %v", deviceID, err)
		return
	}

	log.Printf("WebSocket upgrade successful for device: %s", deviceID)

	// Create MCP handler if config is provided
	var mcpHandler *mcp.WebSocketHandler
	if mcpConfig != nil {
		mcpHandler = mcp.NewWebSocketHandler(mcpConfig)
	}

	client := &Client{
		hub:        hub,
		conn:       conn,
		send:       make(chan []byte, 256),
		deviceID:   deviceID,
		workDir:    workDir,
		executor:   claude.NewExecutor(workDir),
		mcpConfig:  mcpConfig,
		mcpHandler: mcpHandler,
		taskSender: taskSender,
	}

	hub.register <- client

	go client.writePump()
	go client.readPump()
}

func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
		// Clean up MCP handler
		if c.mcpHandler != nil {
			c.mcpHandler.Cleanup()
		}
		// Clean up executor
		if c.executor != nil {
			c.executor.Close()
		}
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Read error: %v", err)
			}
			break
		}

		c.handleMessage(message)
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) handleMessage(data []byte) {
	var msg WSMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		log.Println("Invalid message format:", err)
		return
	}

	switch msg.Type {
	case "command":
		c.handleCommand(msg)
	case "cancel":
		c.handleCancel(msg)
	case "chat_history":
		c.handleChatHistory(msg)
	case "chat_abort":
		c.handleChatAbort(msg)
	case "ping":
		c.sendPong(msg.ID)
	default:
		log.Println("Unknown message type:", msg.Type)
	}
}

func (c *Client) handleCommand(msg WSMessage) {
	var payload CommandPayload
	if err := json.Unmarshal(msg.Payload, &payload); err != nil {
		c.sendError(msg.ID, "Invalid command payload")
		return
	}

	// Send acknowledgment
	c.sendAck(msg.ID)

	// Route to OpenClaw if available
	if c.taskSender != nil {
		go c.executeOpenClawCommand(msg.ID, payload.Text, payload.Skill)
		return
	}

	// Legacy Claude execution is deprecated - return error
	c.sendComplete(msg.ID, "error", nil, "OpenClaw not connected; legacy Claude execution is deprecated. Please connect to OpenClaw gateway.")
}

func (c *Client) handleChatHistory(msg WSMessage) {
	var payload struct {
		Limit int `json:"limit"`
	}
	if err := json.Unmarshal(msg.Payload, &payload); err != nil {
		c.sendError(msg.ID, "Invalid format for chat history limit")
		return
	}

	if c.taskSender == nil {
		c.sendError(msg.ID, "Not connected to OpenClaw gateway")
		return
	}

	c.sendAck(msg.ID)

	go func() {
		var err error
		if ds, ok := c.taskSender.(DeviceAwareTaskSender); ok {
			err = ds.SendChatHistoryForDevice(c.deviceID, payload.Limit)
		} else {
			err = c.taskSender.SendChatHistory(payload.Limit)
		}
		if err != nil {
			c.sendError(msg.ID, fmt.Sprintf("Failed to request chat history: %v", err))
		}
	}()
}

func (c *Client) handleChatAbort(msg WSMessage) {
	var payload struct {
		RunID string `json:"run_id"`
	}
	if err := json.Unmarshal(msg.Payload, &payload); err != nil {
		c.sendError(msg.ID, "Invalid format for chat abort run_id")
		return
	}

	if c.taskSender == nil {
		c.sendError(msg.ID, "Not connected to OpenClaw gateway")
		return
	}

	c.sendAck(msg.ID)

	go func() {
		var err error
		if ds, ok := c.taskSender.(DeviceAwareTaskSender); ok {
			err = ds.SendChatAbortForDevice(c.deviceID, payload.RunID)
		} else {
			err = c.taskSender.SendChatAbort(payload.RunID)
		}
		if err != nil {
			c.sendError(msg.ID, fmt.Sprintf("Failed to abort chat run: %v", err))
		}
	}()
}

func (c *Client) executeOpenClawCommand(commandID, text, skill string) {
	// c.sendStream(commandID, "Sending task to OpenClaw...", "text")
	var reqID string
	var err error
	if ds, ok := c.taskSender.(DeviceAwareTaskSender); ok {
		reqID, err = ds.SendTaskToAgentForDevice(c.deviceID, commandID, text, skill, "p1")
		// Complete is sent by TaskBridge when agent responds (thread isolation)
	} else {
		reqID, err = c.taskSender.SendTaskToAgent(text, skill, "p1")
		if err == nil {
			result := map[string]interface{}{"openclaw_req_id": reqID}
			c.sendComplete(commandID, "success", result, "")
		}
	}
	if err != nil {
		c.sendComplete(commandID, "error", nil, err.Error())
	}
}

func (c *Client) executeCommand(commandID, text, workDir string) {
	// Stream callback
	streamCallback := func(content string, contentType string) {
		c.sendStream(commandID, content, contentType)
	}

	// Execute command
	result, err := c.executor.Execute(text, workDir, streamCallback)

	if err != nil {
		c.sendComplete(commandID, "error", nil, err.Error())
		return
	}

	c.sendComplete(commandID, "success", result, "")
}

func (c *Client) handleCancel(msg WSMessage) {
	var payload struct {
		CommandID string `json:"command_id"`
	}
	if err := json.Unmarshal(msg.Payload, &payload); err != nil {
		return
	}

	c.executor.Cancel(payload.CommandID)
	c.sendComplete(payload.CommandID, "cancelled", nil, "")
}

// Send helpers

func (c *Client) sendJSON(v interface{}) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	select {
	case c.send <- data:
	default:
		// Channel full, drop message
	}
}

func (c *Client) sendAck(id string) {
	c.sendJSON(map[string]interface{}{
		"type": "ack",
		"id":   id,
		"payload": map[string]string{
			"status": "received",
		},
	})
}

func (c *Client) sendStream(commandID, content, contentType string) {
	c.sendJSON(map[string]interface{}{
		"type": "stream",
		"payload": StreamPayload{
			CommandID:   commandID,
			Content:     content,
			ContentType: contentType,
		},
	})
}

func (c *Client) sendComplete(commandID, status string, result map[string]interface{}, errMsg string) {
	c.sendJSON(map[string]interface{}{
		"type": "complete",
		"payload": CompletePayload{
			CommandID: commandID,
			Status:    status,
			Result:    result,
			Error:     errMsg,
		},
	})
}

func (c *Client) sendError(id, message string) {
	c.sendJSON(map[string]interface{}{
		"type": "error",
		"id":   id,
		"payload": map[string]string{
			"message": message,
		},
	})
}

func (c *Client) sendPong(id string) {
	c.sendJSON(map[string]interface{}{
		"type": "pong",
		"id":   id,
	})
}
