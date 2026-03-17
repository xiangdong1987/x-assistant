package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"
)

// CursorClient represents a client for interacting with Cursor via MCP
type CursorClient struct {
	server    *Server
	sessionID string
	mu        sync.RWMutex
}

// NewCursorClient creates a new Cursor client
func NewCursorClient(config *Config) (*CursorClient, error) {
	server, err := NewServer(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create MCP server: %w", err)
	}
	
	return &CursorClient{
		server: server,
	}, nil
}

// Start starts the Cursor client
func (c *CursorClient) Start(ctx context.Context) error {
	if err := c.server.Start(ctx); err != nil {
		return fmt.Errorf("failed to start MCP server: %w", err)
	}
	
	// Create initial session
	session, err := c.server.CreateSession()
	if err != nil {
		c.server.Stop()
		return fmt.Errorf("failed to create session: %w", err)
	}
	
	c.mu.Lock()
	c.sessionID = session.ID
	c.mu.Unlock()
	
	log.Println("Cursor client started")
	return nil
}

// Stop stops the Cursor client
func (c *CursorClient) Stop() error {
	c.mu.Lock()
	if c.sessionID != "" {
		c.server.CloseSession(c.sessionID)
		c.sessionID = ""
	}
	c.mu.Unlock()
	
	if err := c.server.Stop(); err != nil {
		return fmt.Errorf("failed to stop MCP server: %w", err)
	}
	
	log.Println("Cursor client stopped")
	return nil
}

// SendMessage sends a message to Cursor and returns the response
func (c *CursorClient) SendMessage(ctx context.Context, message string) (string, error) {
	c.mu.RLock()
	sessionID := c.sessionID
	c.mu.RUnlock()
	
	if sessionID == "" {
		return "", fmt.Errorf("client not started or session expired")
	}
	
	// Create completion message
	msg := CompletionMessage{
		Role:    "user",
		Content: json.RawMessage(fmt.Sprintf(`"%s"`, jsonEscape(message))),
	}
	
	// Send completion request
	result, err := c.server.SendCompletion(ctx, sessionID, []CompletionMessage{msg}, false)
	if err != nil {
		return "", fmt.Errorf("failed to send completion: %w", err)
	}
	
	// Extract text from result
	var response string
	// result.Message.Content is json.RawMessage, convert to string
	if len(result.Message.Content) > 0 {
		// Try to unmarshal as string first
		var contentStr string
		if err := json.Unmarshal(result.Message.Content, &contentStr); err == nil {
			response = contentStr
		} else {
			// If not a string, use the raw JSON
			response = string(result.Message.Content)
		}
	}
	
	return response, nil
}

// SendMessageStream sends a message to Cursor and streams the response
func (c *CursorClient) SendMessageStream(ctx context.Context, message string, streamCh chan<- string) error {
	c.mu.RLock()
	sessionID := c.sessionID
	c.mu.RUnlock()
	
	if sessionID == "" {
		return fmt.Errorf("client not started or session expired")
	}
	
	// Create completion message
	msg := CompletionMessage{
		Role:    "user",
		Content: json.RawMessage(fmt.Sprintf(`"%s"`, jsonEscape(message))),
	}
	
	// Send streaming completion request
	return c.server.SendCompletionStream(ctx, sessionID, []CompletionMessage{msg}, streamCh)
}

// ExecuteCommand executes a command through Cursor
func (c *CursorClient) ExecuteCommand(ctx context.Context, command string, workingDir string) (string, error) {
	// Format command for Cursor
	message := fmt.Sprintf("Execute command: %s", command)
	if workingDir != "" {
		message = fmt.Sprintf("Execute command in directory %s: %s", workingDir, command)
	}
	
	return c.SendMessage(ctx, message)
}

// AnalyzeCode analyzes code with Cursor
func (c *CursorClient) AnalyzeCode(ctx context.Context, code string, language string) (string, error) {
	message := fmt.Sprintf("Analyze this %s code:\n```%s\n%s\n```", language, language, code)
	return c.SendMessage(ctx, message)
}

// FixCode asks Cursor to fix code issues
func (c *CursorClient) FixCode(ctx context.Context, code string, language string, issue string) (string, error) {
	message := fmt.Sprintf("Fix this issue in the %s code: %s\n\nCode:\n```%s\n%s\n```", 
		language, issue, language, code)
	return c.SendMessage(ctx, message)
}

// ExplainCode asks Cursor to explain code
func (c *CursorClient) ExplainCode(ctx context.Context, code string, language string) (string, error) {
	message := fmt.Sprintf("Explain this %s code:\n```%s\n%s\n```", language, language, code)
	return c.SendMessage(ctx, message)
}

// GenerateCode asks Cursor to generate code
func (c *CursorClient) GenerateCode(ctx context.Context, description string, language string) (string, error) {
	message := fmt.Sprintf("Generate %s code for: %s", language, description)
	return c.SendMessage(ctx, message)
}

// RunTests asks Cursor to run tests
func (c *CursorClient) RunTests(ctx context.Context, testCommand string) (string, error) {
	message := fmt.Sprintf("Run tests with command: %s", testCommand)
	return c.SendMessage(ctx, message)
}

// GetSessionID returns the current session ID
func (c *CursorClient) GetSessionID() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.sessionID
}

// IsConnected returns true if the client is connected
func (c *CursorClient) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.sessionID != "" && c.server != nil
}

// Reconnect reconnects the client
func (c *CursorClient) Reconnect(ctx context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	
	// Stop existing connection
	if c.sessionID != "" {
		c.server.CloseSession(c.sessionID)
		c.sessionID = ""
	}
	
	if c.server != nil {
		c.server.Stop()
	}
	
	// Start new connection
	if err := c.server.Start(ctx); err != nil {
		return fmt.Errorf("failed to restart MCP server: %w", err)
	}
	
	// Create new session
	session, err := c.server.CreateSession()
	if err != nil {
		c.server.Stop()
		return fmt.Errorf("failed to create session: %w", err)
	}
	
	c.sessionID = session.ID
	log.Println("Cursor client reconnected")
	
	return nil
}

// HealthCheck performs a health check
func (c *CursorClient) HealthCheck(ctx context.Context) error {
	c.mu.RLock()
	sessionID := c.sessionID
	c.mu.RUnlock()
	
	if sessionID == "" {
		return fmt.Errorf("client not started")
	}
	
	// Send a simple ping message
	_, err := c.SendMessage(ctx, "Hello")
	if err != nil {
		return fmt.Errorf("health check failed: %w", err)
	}
	
	return nil
}

// jsonEscape escapes a string for JSON
func jsonEscape(s string) string {
	b, err := json.Marshal(s)
	if err != nil {
		return s
	}
	// Remove surrounding quotes
	return string(b[1 : len(b)-1])
}

// ClientFactory creates Cursor clients
type ClientFactory struct {
	config *Config
	mu     sync.RWMutex
	clients map[string]*CursorClient
}

// NewClientFactory creates a new client factory
func NewClientFactory(config *Config) *ClientFactory {
	return &ClientFactory{
		config:  config,
		clients: make(map[string]*CursorClient),
	}
}

// GetOrCreateClient gets or creates a client for a device
func (f *ClientFactory) GetOrCreateClient(deviceID string) (*CursorClient, error) {
	f.mu.RLock()
	client, ok := f.clients[deviceID]
	f.mu.RUnlock()
	
	if ok && client.IsConnected() {
		return client, nil
	}
	
	// Create new client
	f.mu.Lock()
	defer f.mu.Unlock()
	
	// Check again in case another goroutine created it
	if client, ok := f.clients[deviceID]; ok && client.IsConnected() {
		return client, nil
	}
	
	// Create new client
	client, err := NewCursorClient(f.config)
	if err != nil {
		return nil, fmt.Errorf("failed to create cursor client: %w", err)
	}
	
	// Start client
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	
	if err := client.Start(ctx); err != nil {
		return nil, fmt.Errorf("failed to start cursor client: %w", err)
	}
	
	f.clients[deviceID] = client
	return client, nil
}

// RemoveClient removes a client for a device
func (f *ClientFactory) RemoveClient(deviceID string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	
	if client, ok := f.clients[deviceID]; ok {
		client.Stop()
		delete(f.clients, deviceID)
		log.Printf("Removed cursor client for device: %s", deviceID)
	}
}

// Cleanup cleans up all clients
func (f *ClientFactory) Cleanup() {
	f.mu.Lock()
	defer f.mu.Unlock()
	
	for deviceID, client := range f.clients {
		client.Stop()
		delete(f.clients, deviceID)
		log.Printf("Cleaned up cursor client for device: %s", deviceID)
	}
}