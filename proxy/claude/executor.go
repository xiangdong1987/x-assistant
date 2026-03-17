package claude

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"sync"
	"time"

	"claude-voice-proxy/mcp"
)

// StreamCallback is called for each chunk of output
type StreamCallback func(content string, contentType string)

// Executor handles Cursor MCP execution
type Executor struct {
	workDir      string
	mcpConfig    *mcp.Config
	client       *mcp.CursorClient
	mu           sync.RWMutex
	activeTasks  map[string]context.CancelFunc
}

func NewExecutor(workDir string) *Executor {
	// Create MCP configuration
	config := mcp.DefaultConfig()
	config.WorkspaceDir = workDir
	config.TransportType = "stdio" // Use stdio transport for Cursor
	
	return &Executor{
		workDir:     workDir,
		mcpConfig:   config,
		activeTasks: make(map[string]context.CancelFunc),
	}
}

// Execute runs a Cursor command via MCP and streams output
func (e *Executor) Execute(prompt string, workDir string, callback StreamCallback) (map[string]interface{}, error) {
	ctx, cancel := context.WithCancel(context.Background())
	
	// Generate task ID
	taskID := fmt.Sprintf("task-%d", time.Now().UnixNano())
	
	// Store cancellation function
	e.mu.Lock()
	e.activeTasks[taskID] = cancel
	e.mu.Unlock()
	
	defer func() {
		e.mu.Lock()
		delete(e.activeTasks, taskID)
		e.mu.Unlock()
		cancel()
	}()
	
	// Initialize client if needed
	if err := e.ensureClient(ctx); err != nil {
		return nil, fmt.Errorf("failed to initialize MCP client: %w", err)
	}
	
	// Send initial processing message
	callback("Connecting to Cursor via MCP...\n", "text")
	
	// Execute command via MCP
	var result map[string]interface{}
	var finalErr error
	
	// Create a channel for streaming responses
	streamCh := make(chan string, 100)
	
	// Start streaming in goroutine
	go func() {
		defer close(streamCh)
		
		// Use the client to send message
		if err := e.client.SendMessageStream(ctx, prompt, streamCh); err != nil {
			callback(fmt.Sprintf("Error: %v\n", err), "error")
			finalErr = err
			return
		}
	}()
	
	// Read from stream channel
	for chunk := range streamCh {
		select {
		case <-ctx.Done():
			return nil, fmt.Errorf("command cancelled")
		default:
			callback(chunk, "text")
		}
	}
	
	if finalErr != nil {
		return nil, finalErr
	}
	
	// Return success result
	result = map[string]interface{}{
		"status":    "completed",
		"task_id":   taskID,
		"timestamp": time.Now().Format(time.RFC3339),
	}
	
	return result, nil
}

// ensureClient ensures the MCP client is initialized
func (e *Executor) ensureClient(ctx context.Context) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	
	if e.client != nil && e.client.IsConnected() {
		return nil
	}
	
	// Check if Cursor executable exists
	if !e.checkCursorExists() {
		return fmt.Errorf(`Cursor not found at path: %s

Please ensure Cursor is installed and available at one of these locations:
1. /Applications/Cursor.app/Contents/MacOS/Cursor
2. In your PATH as 'cursor'

You can specify the path using --mcp-cursor-path flag:
  go run main.go --mcp-cursor-path="/Applications/Cursor.app/Contents/MacOS/Cursor"

Or install Cursor from: https://cursor.sh`, e.mcpConfig.CursorPath)
	}
	
	// Create new client
	client, err := mcp.NewCursorClient(e.mcpConfig)
	if err != nil {
		return fmt.Errorf("failed to create cursor client: %w", err)
	}
	
	// Start client with timeout
	startCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	
	if err := client.Start(startCtx); err != nil {
		return fmt.Errorf("failed to start cursor client: %w", err)
	}
	
	e.client = client
	log.Println("Cursor MCP client initialized")
	
	return nil
}

// checkCursorExists checks if the Cursor executable exists
func (e *Executor) checkCursorExists() bool {
	// Try to stat the file
	_, err := os.Stat(e.mcpConfig.CursorPath)
	if err == nil {
		return true
	}
	
	// Check if it's in PATH
	if e.mcpConfig.CursorPath == "cursor" {
		path, err := exec.LookPath("cursor")
		if err == nil {
			e.mcpConfig.CursorPath = path
			return true
		}
	}
	
	return false
}

// Cancel stops a running command
func (e *Executor) Cancel(commandID string) {
	e.mu.RLock()
	defer e.mu.RUnlock()
	
	if cancel, ok := e.activeTasks[commandID]; ok {
		cancel()
		log.Printf("Cancelled task: %s", commandID)
	}
}

// Close closes the executor and cleans up resources
func (e *Executor) Close() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	
	// Cancel all active tasks
	for taskID, cancel := range e.activeTasks {
		cancel()
		log.Printf("Cancelled task during close: %s", taskID)
	}
	e.activeTasks = make(map[string]context.CancelFunc)
	
	// Close client
	if e.client != nil {
		if err := e.client.Stop(); err != nil {
			log.Printf("Failed to stop cursor client: %v", err)
		}
		e.client = nil
	}
	
	log.Println("Executor closed")
	return nil
}
