package mcp

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os/exec"
	"sync"
	"time"
)

// Transport defines the interface for MCP transport
type Transport interface {
	// Start starts the transport
	Start(ctx context.Context) error
	
	// Stop stops the transport
	Stop() error
	
	// Send sends a request and returns a response
	Send(ctx context.Context, req *Request) (*Response, error)
	
	// SendNotification sends a notification
	SendNotification(ctx context.Context, notif *Notification) error
	
	// SetMessageHandler sets the message handler
	SetMessageHandler(handler MessageHandler)
	
	// IsConnected returns true if the transport is connected
	IsConnected() bool
}

// MessageHandler handles incoming messages
type MessageHandler func(msg []byte) error

// StdioTransport implements stdio transport for MCP
type StdioTransport struct {
	config     *Config
	cmd        *exec.Cmd
	stdin      io.WriteCloser
	stdout     io.ReadCloser
	stderr     io.ReadCloser
	scanner    *bufio.Scanner
	handler    MessageHandler
	mu         sync.RWMutex
	connected  bool
	cancel     context.CancelFunc
	requestID  int
	responses  map[string]chan *Response
	responsesMu sync.RWMutex
}

// NewStdioTransport creates a new stdio transport
func NewStdioTransport(config *Config) *StdioTransport {
	return &StdioTransport{
		config:    config,
		responses: make(map[string]chan *Response),
	}
}

// Start starts the stdio transport
func (t *StdioTransport) Start(ctx context.Context) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	
	if t.connected {
		return fmt.Errorf("transport already started")
	}
	
	// Create command
	t.cmd = exec.CommandContext(ctx, t.config.CursorPath, "--mcp")
	
	// Setup pipes
	var err error
	t.stdin, err = t.cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("failed to create stdin pipe: %w", err)
	}
	
	t.stdout, err = t.cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("failed to create stdout pipe: %w", err)
	}
	
	t.stderr, err = t.cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("failed to create stderr pipe: %w", err)
	}
	
	// Set working directory
	t.cmd.Dir = t.config.WorkspaceDir
	
	// Start command
	if err := t.cmd.Start(); err != nil {
		return fmt.Errorf("failed to start cursor: %w", err)
	}
	
	// Create scanner for stdout
	t.scanner = bufio.NewScanner(t.stdout)
	t.scanner.Buffer(make([]byte, 1024*1024), 1024*1024) // 1MB buffer
	
	// Start reading stderr in background
	go t.readStderr()
	
	// Start reading stdout in background
	ctx, cancel := context.WithCancel(ctx)
	t.cancel = cancel
	go t.readLoop(ctx)
	
	t.connected = true
	log.Printf("Stdio transport started with cursor at: %s", t.config.CursorPath)
	
	return nil
}

// Stop stops the stdio transport
func (t *StdioTransport) Stop() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	
	if !t.connected {
		return nil
	}
	
	if t.cancel != nil {
		t.cancel()
	}
	
	// Close stdin to signal EOF
	if t.stdin != nil {
		t.stdin.Close()
	}
	
	// Wait for command to exit
	if t.cmd != nil && t.cmd.Process != nil {
		t.cmd.Process.Kill()
		t.cmd.Wait()
	}
	
	t.connected = false
	log.Println("Stdio transport stopped")
	
	return nil
}

// Send sends a request and returns a response
func (t *StdioTransport) Send(ctx context.Context, req *Request) (*Response, error) {
	if !t.IsConnected() {
		return nil, fmt.Errorf("transport not connected")
	}
	
	// Generate request ID if not provided
	if req.ID == nil {
		t.requestID++
		id := fmt.Sprintf("%d", t.requestID)
		req.ID = json.RawMessage(fmt.Sprintf(`"%s"`, id))
	}
	
	// Marshal request
	data, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}
	
	// Create response channel
	idBytes, _ := req.ID.MarshalJSON()
	idStr := string(idBytes)
	
	respChan := make(chan *Response, 1)
	t.responsesMu.Lock()
	t.responses[idStr] = respChan
	t.responsesMu.Unlock()
	
	// Clean up response channel
	defer func() {
		t.responsesMu.Lock()
		delete(t.responses, idStr)
		t.responsesMu.Unlock()
	}()
	
	// Send request
	t.mu.RLock()
	_, err = t.stdin.Write(append(data, '\n'))
	t.mu.RUnlock()
	
	if err != nil {
		return nil, fmt.Errorf("failed to write to stdin: %w", err)
	}
	
	// Wait for response
	select {
	case resp := <-respChan:
		return resp, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(30 * time.Second):
		return nil, fmt.Errorf("request timeout")
	}
}

// SendNotification sends a notification
func (t *StdioTransport) SendNotification(ctx context.Context, notif *Notification) error {
	if !t.IsConnected() {
		return fmt.Errorf("transport not connected")
	}
	
	// Marshal notification
	data, err := json.Marshal(notif)
	if err != nil {
		return fmt.Errorf("failed to marshal notification: %w", err)
	}
	
	// Send notification
	t.mu.RLock()
	_, err = t.stdin.Write(append(data, '\n'))
	t.mu.RUnlock()
	
	if err != nil {
		return fmt.Errorf("failed to write to stdin: %w", err)
	}
	
	return nil
}

// SetMessageHandler sets the message handler
func (t *StdioTransport) SetMessageHandler(handler MessageHandler) {
	t.handler = handler
}

// IsConnected returns true if the transport is connected
func (t *StdioTransport) IsConnected() bool {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.connected
}

// readLoop reads messages from stdout
func (t *StdioTransport) readLoop(ctx context.Context) {
	for t.scanner.Scan() {
		select {
		case <-ctx.Done():
			return
		default:
			line := t.scanner.Text()
			if line == "" {
				continue
			}
			
			// Parse message
			if err := t.handleMessage([]byte(line)); err != nil {
				log.Printf("Failed to handle message: %v", err)
			}
		}
	}
	
	if err := t.scanner.Err(); err != nil {
		log.Printf("Scanner error: %v", err)
	}
	
	t.mu.Lock()
	t.connected = false
	t.mu.Unlock()
}

// handleMessage handles an incoming message
func (t *StdioTransport) handleMessage(data []byte) error {
	// Try to parse as response first
	if resp, err := ParseResponse(data); err == nil {
		return t.handleResponse(resp)
	}
	
	// Try to parse as notification
	if notif, err := ParseNotification(data); err == nil {
		return t.handleNotification(notif)
	}
	
	// Try to parse as request (server can send requests too)
	if req, err := ParseRequest(data); err == nil {
		return t.handleRequest(req)
	}
	
	// Call message handler if set
	if t.handler != nil {
		return t.handler(data)
	}
	
	return fmt.Errorf("failed to parse message: %s", string(data))
}

// handleResponse handles a response
func (t *StdioTransport) handleResponse(resp *Response) error {
	idBytes, _ := resp.ID.MarshalJSON()
	idStr := string(idBytes)
	
	t.responsesMu.RLock()
	respChan, ok := t.responses[idStr]
	t.responsesMu.RUnlock()
	
	if ok {
		select {
		case respChan <- resp:
		default:
			// Channel full, drop response
		}
	}
	
	return nil
}

// handleNotification handles a notification
func (t *StdioTransport) handleNotification(notif *Notification) error {
	// For now, just log notifications
	log.Printf("Received notification: %s", notif.Method)
	return nil
}

// handleRequest handles a request from the server
func (t *StdioTransport) handleRequest(req *Request) error {
	// For now, just log requests from server
	log.Printf("Received request from server: %s", req.Method)
	return nil
}

// readStderr reads from stderr and logs it
func (t *StdioTransport) readStderr() {
	scanner := bufio.NewScanner(t.stderr)
	for scanner.Scan() {
		log.Printf("Cursor stderr: %s", scanner.Text())
	}
}

// HTTPTransport implements HTTP transport for MCP
type HTTPTransport struct {
	config    *Config
	client    *http.Client
	baseURL   string
	handler   MessageHandler
	mu        sync.RWMutex
	connected bool
}

// NewHTTPTransport creates a new HTTP transport
func NewHTTPTransport(config *Config) *HTTPTransport {
	return &HTTPTransport{
		config: config,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// Start starts the HTTP transport
func (t *HTTPTransport) Start(ctx context.Context) error {
	t.mu.Lock()
	defer t.mu.Unlock()
	
	if t.connected {
		return fmt.Errorf("transport already started")
	}
	
	t.baseURL = fmt.Sprintf("http://%s:%d", t.config.HTTPHost, t.config.HTTPPort)
	t.connected = true
	log.Printf("HTTP transport started with base URL: %s", t.baseURL)
	
	return nil
}

// Stop stops the HTTP transport
func (t *HTTPTransport) Stop() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	
	t.connected = false
	log.Println("HTTP transport stopped")
	
	return nil
}

// Send sends a request and returns a response
func (t *HTTPTransport) Send(ctx context.Context, req *Request) (*Response, error) {
	if !t.IsConnected() {
		return nil, fmt.Errorf("transport not connected")
	}
	
	// Marshal request
	data, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}
	
	// Create HTTP request
	httpReq, err := http.NewRequestWithContext(ctx, "POST", t.baseURL, bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("failed to create HTTP request: %w", err)
	}
	
	httpReq.Header.Set("Content-Type", "application/json")
	
	// Send request
	resp, err := t.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to send HTTP request: %w", err)
	}
	defer resp.Body.Close()
	
	// Read response
	respData, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}
	
	// Parse response
	return ParseResponse(respData)
}

// SendNotification sends a notification
func (t *HTTPTransport) SendNotification(ctx context.Context, notif *Notification) error {
	// HTTP transport doesn't support notifications directly
	// Convert notification to request
	req := &Request{
		JSONRPC: notif.JSONRPC,
		Method:  notif.Method,
		Params:  notif.Params,
	}
	
	_, err := t.Send(ctx, req)
	return err
}

// SetMessageHandler sets the message handler
func (t *HTTPTransport) SetMessageHandler(handler MessageHandler) {
	t.handler = handler
}

// IsConnected returns true if the transport is connected
func (t *HTTPTransport) IsConnected() bool {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.connected
}

// NewTransport creates a new transport based on configuration
func NewTransport(config *Config) (Transport, error) {
	switch config.TransportType {
	case "stdio":
		return NewStdioTransport(config), nil
	case "http":
		return NewHTTPTransport(config), nil
	default:
		return nil, fmt.Errorf("unsupported transport type: %s", config.TransportType)
	}
}