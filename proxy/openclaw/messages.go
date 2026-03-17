package openclaw

import "encoding/json"

// ---- Outbound messages (XAssistant → Gateway) ----

// Frame is the base WebSocket message frame
type Frame struct {
	Type   string          `json:"type"`             // "req", "res", "event"
	ID     string          `json:"id,omitempty"`     // request/response correlation ID
	Method string          `json:"method,omitempty"` // for "req" type
	Params json.RawMessage `json:"params,omitempty"` // for "req" type
}

// ConnectParams is sent after receiving connect.challenge
type ConnectParams struct {
	MinProtocol int             `json:"minProtocol"`
	MaxProtocol int             `json:"maxProtocol"`
	Client      ConnectClient   `json:"client"`
	Role        string          `json:"role"`
	Scopes      []string        `json:"scopes"`
	Caps        []string        `json:"caps"`
	Commands    []string        `json:"commands"`
	Permissions map[string]bool `json:"permissions"`
	Auth        ConnectAuth     `json:"auth"`
	Locale      string          `json:"locale,omitempty"`
	UserAgent   string          `json:"userAgent,omitempty"`
	Device      *DeviceInfo     `json:"device,omitempty"`
}

// ConnectAuth contains authentication credentials
type ConnectAuth struct {
	Token       string `json:"token"`
	DeviceToken string `json:"deviceToken,omitempty"`
}

type ConnectClient struct {
	ID       string `json:"id"` // must be: "cli", "web", "macos", or "node"
	Version  string `json:"version"`
	Platform string `json:"platform"` // e.g. "macos", "linux", "node"
	Mode     string `json:"mode"`     // e.g. "operator", "backend"
}

// DeviceInfo contains device identity and challenge signature
type DeviceInfo struct {
	ID        string `json:"id"`
	PublicKey string `json:"publicKey"`
	Nonce     string `json:"nonce"`
	Signature string `json:"signature"`
	SignedAt  int64  `json:"signedAt"`
}

// ChatSendParams is the payload for chat.send requests
type ChatSendParams struct {
	SessionKey     string `json:"sessionKey"`
	Message        string `json:"message"`
	IdempotencyKey string `json:"idempotencyKey"`
	TimeoutMs      int    `json:"timeoutMs,omitempty"`
	Thinking       string `json:"thinking,omitempty"`
}

// ChatHistoryParams is the payload for chat.history requests
type ChatHistoryParams struct {
	SessionKey string `json:"sessionKey"`
	Limit      int    `json:"limit,omitempty"`
}

// ChatAbortParams is the payload for chat.abort requests
type ChatAbortParams struct {
	SessionKey string `json:"sessionKey"`
	RunID      string `json:"runId"`
}

// ---- Inbound messages (Gateway → XAssistant) ----

// Response is a Gateway response to a request
type Response struct {
	Type    string          `json:"type"` // "res"
	ID      string          `json:"id"`   // correlation ID
	OK      bool            `json:"ok"`
	Payload json.RawMessage `json:"payload,omitempty"`
	Error   *ErrorPayload   `json:"error,omitempty"`
}

type ErrorPayload struct {
	Code    string `json:"code,omitempty"`
	Message string `json:"message"`
}

// ConnectResponse is the payload of a successful connect response
type ConnectResponse struct {
	DeviceToken string `json:"deviceToken"`
	SessionID   string `json:"sessionId"`
}

// Event is a server-push event from the Gateway
type Event struct {
	Type         string          `json:"type"`  // "event"
	EventName    string          `json:"event"` // "agent", "chat", "presence", etc.
	Payload      json.RawMessage `json:"payload"`
	Seq          int64           `json:"seq,omitempty"`
	StateVersion json.RawMessage `json:"stateVersion,omitempty"`
}

// AgentEventPayload represents an agent task event
type AgentEventPayload struct {
	Action     string          `json:"action,omitempty"` // "task_start", "task_progress", "task_complete", "task_error"
	Task       AgentTaskInfo   `json:"task,omitempty"`
	Stream     string          `json:"stream,omitempty"`     // "assistant", "lifecycle" etc.
	SessionKey string          `json:"sessionKey,omitempty"` // e.g. "agent:main:main"
	Data       AgentStreamData `json:"data,omitempty"`
}

type AgentStreamData struct {
	Text   string `json:"text,omitempty"`
	Delta  string `json:"delta,omitempty"`
	Phase  string `json:"phase,omitempty"` // lifecycle: "start" | "end" | "error"
	Reason string `json:"reason,omitempty"` // stream error reason
}

type AgentTaskInfo struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description,omitempty"`
	Result      string `json:"result,omitempty"`
	Status      string `json:"status"` // "pending", "running", "completed", "error"
	Skill       string `json:"skill,omitempty"`
	Error       string `json:"error,omitempty"`
}

// ChatEventPayload represents a chat message event in v2
type ChatEventPayload struct {
	RunID      string `json:"runId,omitempty"`
	SessionKey string `json:"sessionKey,omitempty"`
	Seq        int64  `json:"seq,omitempty"`
	State      string `json:"state,omitempty"` // "delta", "final", "aborted", or "error"
	Message    struct {
		Role    string `json:"role"`
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
		Timestamp int64 `json:"timestamp"`
	} `json:"message"`
}

// HeartbeatPayload is the heartbeat event payload
type HeartbeatPayload struct {
	Timestamp int64 `json:"ts"`
}

// ---- Task types for bridging to XAssistant ----

// TaskPush is the message format pushed to Flutter clients via the Hub
type TaskPush struct {
	Type   string   `json:"type"`   // "openclaw_task"
	Action string   `json:"action"` // "create", "update", "complete", "error"
	Task   TaskData `json:"task"`
}

type TaskData struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description,omitempty"`
	Priority    string `json:"priority"` // "p0", "p1", "p2", "p3"
	Source      string `json:"source"`   // "openClaw"
	Status      string `json:"status"`   // "pending", "inProgress", "completed", "waitingFeedback"
	Feedback    string `json:"feedback,omitempty"`
	Result      string `json:"result,omitempty"`
}
