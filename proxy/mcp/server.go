package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"
)

// Server represents an MCP server
type Server struct {
	config     *Config
	transport  Transport
	sessions   map[string]*Session
	sessionsMu sync.RWMutex
	handlers   map[string]RequestHandler
	initialized bool
	mu         sync.RWMutex
}

// Session represents a client session
type Session struct {
	ID         string
	CreatedAt  time.Time
	LastActive time.Time
	Context    context.Context
	Cancel     context.CancelFunc
	Messages   []CompletionMessage
}

// RequestHandler handles MCP requests
type RequestHandler func(ctx context.Context, req *Request, session *Session) (*Response, error)

// NewServer creates a new MCP server
func NewServer(config *Config) (*Server, error) {
	if err := config.Validate(); err != nil {
		return nil, fmt.Errorf("invalid configuration: %w", err)
	}
	
	transport, err := NewTransport(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create transport: %w", err)
	}
	
	server := &Server{
		config:    config,
		transport: transport,
		sessions:  make(map[string]*Session),
		handlers:  make(map[string]RequestHandler),
	}
	
	// Register default handlers
	server.registerHandlers()
	
	return server, nil
}

// Start starts the MCP server
func (s *Server) Start(ctx context.Context) error {
	// Start transport
	if err := s.transport.Start(ctx); err != nil {
		return fmt.Errorf("failed to start transport: %w", err)
	}
	
	// Set message handler
	s.transport.SetMessageHandler(s.handleIncomingMessage)
	
	// Initialize MCP connection
	if err := s.initialize(ctx); err != nil {
		s.transport.Stop()
		return fmt.Errorf("failed to initialize MCP connection: %w", err)
	}
	
	log.Printf("MCP server started with %s transport", s.config.TransportType)
	
	// Start session cleanup goroutine
	go s.sessionCleanupLoop(ctx)
	
	return nil
}

// Stop stops the MCP server
func (s *Server) Stop() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	
	// Cancel all sessions
	s.sessionsMu.Lock()
	for _, session := range s.sessions {
		if session.Cancel != nil {
			session.Cancel()
		}
	}
	s.sessions = make(map[string]*Session)
	s.sessionsMu.Unlock()
	
	// Stop transport
	if err := s.transport.Stop(); err != nil {
		return fmt.Errorf("failed to stop transport: %w", err)
	}
	
	s.initialized = false
	log.Println("MCP server stopped")
	
	return nil
}

// initialize initializes the MCP connection
func (s *Server) initialize(ctx context.Context) error {
	// Create initialization request
	params := InitializeParams{
		ProtocolVersion: "2024-11-05",
		Capabilities: ClientCapabilities{
			Sampling: &SamplingCapabilities{
				Available: true,
			},
		},
		ClientInfo: &ClientInfo{
			Name:    "claude-voice-proxy",
			Version: "1.0.0",
		},
	}
	
	paramsData, err := json.Marshal(params)
	if err != nil {
		return fmt.Errorf("failed to marshal initialize params: %w", err)
	}
	
	req := &Request{
		JSONRPC: JSONRPC20,
		Method:  MethodInitialize,
		Params:  paramsData,
		ID:      json.RawMessage(`"init"`),
	}
	
	// Send initialization request
	resp, err := s.transport.Send(ctx, req)
	if err != nil {
		return fmt.Errorf("failed to send initialize request: %w", err)
	}
	
	if resp.Error != nil {
		return fmt.Errorf("initialize error: %s", resp.Error.Message)
	}
	
	// Parse initialization result
	var result InitializeResult
	if err := json.Unmarshal(resp.Result, &result); err != nil {
		return fmt.Errorf("failed to parse initialize result: %w", err)
	}
	
	// Send initialized notification
	notif := &Notification{
		JSONRPC: JSONRPC20,
		Method:  MethodInitialized,
	}
	
	if err := s.transport.SendNotification(ctx, notif); err != nil {
		return fmt.Errorf("failed to send initialized notification: %w", err)
	}
	
	s.mu.Lock()
	s.initialized = true
	s.mu.Unlock()
	
	log.Printf("MCP connection initialized with server: %s %s", 
		result.ServerInfo.Name, result.ServerInfo.Version)
	
	return nil
}

// CreateSession creates a new session
func (s *Server) CreateSession() (*Session, error) {
	sessionID := generateSessionID()
	
	ctx, cancel := context.WithCancel(context.Background())
	
	session := &Session{
		ID:         sessionID,
		CreatedAt:  time.Now(),
		LastActive: time.Now(),
		Context:    ctx,
		Cancel:     cancel,
		Messages:   make([]CompletionMessage, 0),
	}
	
	s.sessionsMu.Lock()
	s.sessions[sessionID] = session
	s.sessionsMu.Unlock()
	
	log.Printf("Created new session: %s", sessionID)
	
	return session, nil
}

// GetSession gets a session by ID
func (s *Server) GetSession(sessionID string) (*Session, bool) {
	s.sessionsMu.RLock()
	session, ok := s.sessions[sessionID]
	s.sessionsMu.RUnlock()
	
	if ok {
		session.LastActive = time.Now()
	}
	
	return session, ok
}

// CloseSession closes a session
func (s *Server) CloseSession(sessionID string) {
	s.sessionsMu.Lock()
	session, ok := s.sessions[sessionID]
	if ok {
		if session.Cancel != nil {
			session.Cancel()
		}
		delete(s.sessions, sessionID)
		log.Printf("Closed session: %s", sessionID)
	}
	s.sessionsMu.Unlock()
}

// SendCompletion sends a completion request
func (s *Server) SendCompletion(ctx context.Context, sessionID string, messages []CompletionMessage, stream bool) (*CompletionResult, error) {
	s.mu.RLock()
	if !s.initialized {
		s.mu.RUnlock()
		return nil, fmt.Errorf("server not initialized")
	}
	s.mu.RUnlock()
	
	// Get or create session
	session, ok := s.GetSession(sessionID)
	if !ok {
		var err error
		session, err = s.CreateSession()
		if err != nil {
			return nil, fmt.Errorf("failed to create session: %w", err)
		}
	}
	
	// Update session messages
	session.Messages = append(session.Messages, messages...)
	session.LastActive = time.Now()
	
	// Create completion request
	params := CompletionParams{
		Messages: session.Messages,
		Stream:   stream,
	}
	
	paramsData, err := json.Marshal(params)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal completion params: %w", err)
	}
	
	req := &Request{
		JSONRPC: JSONRPC20,
		Method:  MethodCompletionCreate,
		Params:  paramsData,
		ID:      json.RawMessage(fmt.Sprintf(`"comp-%s-%d"`, sessionID, time.Now().UnixNano())),
	}
	
	// Send request
	resp, err := s.transport.Send(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("failed to send completion request: %w", err)
	}
	
	if resp.Error != nil {
		return nil, fmt.Errorf("completion error: %s", resp.Error.Message)
	}
	
	// Parse completion result
	var result CompletionResult
	if err := json.Unmarshal(resp.Result, &result); err != nil {
		return nil, fmt.Errorf("failed to parse completion result: %w", err)
	}
	
	// Add assistant response to session messages
	session.Messages = append(session.Messages, result.Message)
	
	return &result, nil
}

// SendCompletionStream sends a streaming completion request
func (s *Server) SendCompletionStream(ctx context.Context, sessionID string, messages []CompletionMessage, streamCh chan<- string) error {
	// For now, implement non-streaming version
	// TODO: Implement proper streaming support
	result, err := s.SendCompletion(ctx, sessionID, messages, false)
	if err != nil {
		return err
	}
	
	// Extract text from result
	var contentStr string
	// result.Message.Content is json.RawMessage
	if len(result.Message.Content) > 0 {
		// Try to unmarshal as string first
		var str string
		if err := json.Unmarshal(result.Message.Content, &str); err == nil {
			contentStr = str
		} else {
			// If not a string, use the raw JSON
			contentStr = string(result.Message.Content)
		}
	}
	
	select {
	case streamCh <- contentStr:
	case <-ctx.Done():
		return ctx.Err()
	}
	
	close(streamCh)
	return nil
}

// registerHandlers registers default request handlers
func (s *Server) registerHandlers() {
	s.handlers[MethodToolsList] = s.handleToolsList
	s.handlers[MethodToolsCall] = s.handleToolsCall
	s.handlers[MethodResourcesList] = s.handleResourcesList
	s.handlers[MethodResourcesRead] = s.handleResourcesRead
	s.handlers[MethodPromptsList] = s.handlePromptsList
	s.handlers[MethodPromptsGet] = s.handlePromptsGet
}

// handleIncomingMessage handles incoming messages from transport
func (s *Server) handleIncomingMessage(data []byte) error {
	// Try to parse as request
	req, err := ParseRequest(data)
	if err == nil {
		return s.handleRequest(context.Background(), req, nil)
	}
	
	// Try to parse as notification
	notif, err := ParseNotification(data)
	if err == nil {
		return s.handleNotification(context.Background(), notif)
	}
	
	log.Printf("Failed to parse incoming message: %s", string(data))
	return nil
}

// handleRequest handles an incoming request
func (s *Server) handleRequest(ctx context.Context, req *Request, session *Session) error {
	handler, ok := s.handlers[req.Method]
	if !ok {
		log.Printf("No handler for method: %s", req.Method)
		return nil
	}
	
	resp, err := handler(ctx, req, session)
	if err != nil {
		log.Printf("Handler error for method %s: %v", req.Method, err)
		return err
	}
	
	// Send response if we have a transport
	if s.transport != nil && req.ID != nil {
		resp.ID = req.ID
		resp.JSONRPC = JSONRPC20
		// TODO: Send response back through transport
	}
	
	return nil
}

// handleNotification handles an incoming notification
func (s *Server) handleNotification(ctx context.Context, notif *Notification) error {
	log.Printf("Received notification: %s", notif.Method)
	return nil
}

// Default handlers
func (s *Server) handleToolsList(ctx context.Context, req *Request, session *Session) (*Response, error) {
	tools := []Tool{
		{
			Name:        "execute_command",
			Description: "Execute a shell command",
			InputSchema: json.RawMessage(`{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}`),
		},
		{
			Name:        "read_file",
			Description: "Read a file",
			InputSchema: json.RawMessage(`{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}`),
		},
		{
			Name:        "write_file",
			Description: "Write to a file",
			InputSchema: json.RawMessage(`{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}`),
		},
	}
	
	result, err := json.Marshal(map[string]interface{}{
		"tools": tools,
	})
	if err != nil {
		return nil, err
	}
	
	return &Response{
		JSONRPC: JSONRPC20,
		Result:  result,
	}, nil
}

func (s *Server) handleToolsCall(ctx context.Context, req *Request, session *Session) (*Response, error) {
	var params ToolCallParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		return nil, fmt.Errorf("failed to parse tool call params: %w", err)
	}
	
	// TODO: Implement actual tool execution
	content := []ToolCallContent{
		{
			Type: "text",
			Text: fmt.Sprintf("Tool '%s' called with arguments: %s", params.Name, string(params.Arguments)),
		},
	}
	
	result, err := json.Marshal(ToolCallResult{
		Content: content,
	})
	if err != nil {
		return nil, err
	}
	
	return &Response{
		JSONRPC: JSONRPC20,
		Result:  result,
	}, nil
}

func (s *Server) handleResourcesList(ctx context.Context, req *Request, session *Session) (*Response, error) {
	result, err := json.Marshal(map[string]interface{}{
		"resources": []interface{}{},
	})
	if err != nil {
		return nil, err
	}
	
	return &Response{
		JSONRPC: JSONRPC20,
		Result:  result,
	}, nil
}

func (s *Server) handleResourcesRead(ctx context.Context, req *Request, session *Session) (*Response, error) {
	result, err := json.Marshal(map[string]interface{}{
		"contents": []interface{}{},
	})
	if err != nil {
		return nil, err
	}
	
	return &Response{
		JSONRPC: JSONRPC20,
		Result:  result,
	}, nil
}

func (s *Server) handlePromptsList(ctx context.Context, req *Request, session *Session) (*Response, error) {
	result, err := json.Marshal(map[string]interface{}{
		"prompts": []interface{}{},
	})
	if err != nil {
		return nil, err
	}
	
	return &Response{
		JSONRPC: JSONRPC20,
		Result:  result,
	}, nil
}

func (s *Server) handlePromptsGet(ctx context.Context, req *Request, session *Session) (*Response, error) {
	result, err := json.Marshal(map[string]interface{}{
		"description": "No prompts available",
	})
	if err != nil {
		return nil, err
	}
	
	return &Response{
		JSONRPC: JSONRPC20,
		Result:  result,
	}, nil
}

// sessionCleanupLoop periodically cleans up expired sessions
func (s *Server) sessionCleanupLoop(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.cleanupExpiredSessions()
		}
	}
}

// cleanupExpiredSessions cleans up sessions that have expired
func (s *Server) cleanupExpiredSessions() {
	expiryTime := time.Now().Add(-time.Duration(s.config.SessionTimeout) * time.Second)
	
	s.sessionsMu.Lock()
	defer s.sessionsMu.Unlock()
	
	for id, session := range s.sessions {
		if session.LastActive.Before(expiryTime) {
			if session.Cancel != nil {
				session.Cancel()
			}
			delete(s.sessions, id)
			log.Printf("Cleaned up expired session: %s", id)
		}
	}
}

// generateSessionID generates a unique session ID
func generateSessionID() string {
	return fmt.Sprintf("sess-%d", time.Now().UnixNano())
}