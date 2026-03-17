package mcp

import (
	"encoding/json"
	"fmt"
)

// JSON-RPC 2.0 message types
type JSONRPCVersion string

const (
	JSONRPC20 JSONRPCVersion = "2.0"
)

// Request represents a JSON-RPC 2.0 request
type Request struct {
	JSONRPC JSONRPCVersion `json:"jsonrpc"`
	Method  string         `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
	ID      json.RawMessage `json:"id,omitempty"`
}

// Response represents a JSON-RPC 2.0 response
type Response struct {
	JSONRPC JSONRPCVersion `json:"jsonrpc"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *Error         `json:"error,omitempty"`
	ID      json.RawMessage `json:"id"`
}

// Error represents a JSON-RPC 2.0 error
type Error struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data,omitempty"`
}

// Notification represents a JSON-RPC 2.0 notification
type Notification struct {
	JSONRPC JSONRPCVersion `json:"jsonrpc"`
	Method  string         `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

// MCP-specific message types
const (
	// Initialization
	MethodInitialize = "initialize"
	MethodInitialized = "initialized"
	
	// Tools
	MethodToolsList = "tools/list"
	MethodToolsCall = "tools/call"
	
	// Resources
	MethodResourcesList = "resources/list"
	MethodResourcesRead = "resources/read"
	
	// Prompts
	MethodPromptsList = "prompts/list"
	MethodPromptsGet  = "prompts/get"
	
	// Completion
	MethodCompletionCreate = "completion/create"
	
	// Notifications
	MethodNotify = "notifications/notify"
)

// InitializeParams represents initialization parameters
type InitializeParams struct {
	ProtocolVersion string                 `json:"protocolVersion"`
	Capabilities    ClientCapabilities     `json:"capabilities"`
	ClientInfo      *ClientInfo            `json:"clientInfo,omitempty"`
}

// ClientCapabilities represents client capabilities
type ClientCapabilities struct {
	Sampling *SamplingCapabilities `json:"sampling,omitempty"`
}

// SamplingCapabilities represents sampling capabilities
type SamplingCapabilities struct {
	Available bool `json:"available"`
}

// ClientInfo represents client information
type ClientInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

// InitializeResult represents initialization result
type InitializeResult struct {
	ProtocolVersion string                 `json:"protocolVersion"`
	Capabilities    ServerCapabilities     `json:"capabilities"`
	ServerInfo      *ServerInfo            `json:"serverInfo,omitempty"`
}

// ServerCapabilities represents server capabilities
type ServerCapabilities struct {
	Tools     *ToolsCapabilities     `json:"tools,omitempty"`
	Resources *ResourcesCapabilities `json:"resources,omitempty"`
	Prompts   *PromptsCapabilities   `json:"prompts,omitempty"`
}

// ToolsCapabilities represents tools capabilities
type ToolsCapabilities struct {
	ListChanged bool `json:"listChanged"`
}

// ResourcesCapabilities represents resources capabilities
type ResourcesCapabilities struct {
	ListChanged bool `json:"listChanged"`
	Subscribe   bool `json:"subscribe"`
}

// PromptsCapabilities represents prompts capabilities
type PromptsCapabilities struct {
	ListChanged bool `json:"listChanged"`
}

// ServerInfo represents server information
type ServerInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

// Tool represents an MCP tool
type Tool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	InputSchema json.RawMessage `json:"inputSchema"`
}

// ToolCallParams represents tool call parameters
type ToolCallParams struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}

// ToolCallResult represents tool call result
type ToolCallResult struct {
	Content []ToolCallContent `json:"content"`
	IsError bool              `json:"isError,omitempty"`
}

// ToolCallContent represents tool call content
type ToolCallContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// CompletionParams represents completion parameters
type CompletionParams struct {
	Messages []CompletionMessage `json:"messages"`
	Stream   bool                `json:"stream,omitempty"`
}

// CompletionMessage represents a completion message
type CompletionMessage struct {
	Role    string          `json:"role"`
	Content json.RawMessage `json:"content"`
}

// CompletionResult represents completion result
type CompletionResult struct {
	Model     string          `json:"model"`
	Message   CompletionMessage `json:"message"`
	StopReason string         `json:"stop_reason,omitempty"`
}

// ParseRequest parses a JSON-RPC request from bytes
func ParseRequest(data []byte) (*Request, error) {
	var req Request
	if err := json.Unmarshal(data, &req); err != nil {
		return nil, fmt.Errorf("failed to parse request: %w", err)
	}
	return &req, nil
}

// ParseResponse parses a JSON-RPC response from bytes
func ParseResponse(data []byte) (*Response, error) {
	var resp Response
	if err := json.Unmarshal(data, &resp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}
	return &resp, nil
}

// ParseNotification parses a JSON-RPC notification from bytes
func ParseNotification(data []byte) (*Notification, error) {
	var notif Notification
	if err := json.Unmarshal(data, &notif); err != nil {
		return nil, fmt.Errorf("failed to parse notification: %w", err)
	}
	return &notif, nil
}