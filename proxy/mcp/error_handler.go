package mcp

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"
)

// ErrorType represents the type of error
type ErrorType string

const (
	// Connection errors
	ErrorConnectionFailed  ErrorType = "connection_failed"
	ErrorConnectionLost    ErrorType = "connection_lost"
	ErrorTransportFailed   ErrorType = "transport_failed"
	
	// Authentication errors
	ErrorAuthFailed        ErrorType = "auth_failed"
	ErrorSessionExpired    ErrorType = "session_expired"
	
	// Request errors
	ErrorRequestTimeout    ErrorType = "request_timeout"
	ErrorRequestFailed     ErrorType = "request_failed"
	ErrorInvalidResponse   ErrorType = "invalid_response"
	
	// Resource errors
	ErrorResourceExhausted ErrorType = "resource_exhausted"
	ErrorRateLimited       ErrorType = "rate_limited"
	
	// Internal errors
	ErrorInternal          ErrorType = "internal_error"
)

// MCError represents an MCP error
type MCError struct {
	Type    ErrorType `json:"type"`
	Message string    `json:"message"`
	Details string    `json:"details,omitempty"`
	Retryable bool    `json:"retryable"`
	RetryAfter *time.Duration `json:"retry_after,omitempty"`
}

// Error implements error interface
func (e *MCError) Error() string {
	return fmt.Sprintf("%s: %s", e.Type, e.Message)
}

// IsRetryable returns true if the error is retryable
func (e *MCError) IsRetryable() bool {
	return e.Retryable
}

// NewError creates a new error
func NewError(errorType ErrorType, message string, details string) *MCError {
	retryable := isErrorRetryable(errorType)
	return &MCError{
		Type:      errorType,
		Message:   message,
		Details:   details,
		Retryable: retryable,
	}
}

// NewErrorWithRetry creates a new error with retry after duration
func NewErrorWithRetry(errorType ErrorType, message string, details string, retryAfter time.Duration) *MCError {
	err := NewError(errorType, message, details)
	err.RetryAfter = &retryAfter
	return err
}

// isErrorRetryable determines if an error type is retryable
func isErrorRetryable(errorType ErrorType) bool {
	switch errorType {
	case ErrorConnectionFailed, ErrorConnectionLost, ErrorTransportFailed,
		 ErrorRequestTimeout, ErrorRateLimited:
		return true
	case ErrorAuthFailed, ErrorSessionExpired, ErrorRequestFailed,
		 ErrorInvalidResponse, ErrorResourceExhausted, ErrorInternal:
		return false
	default:
		return false
	}
}

// RetryManager manages retry logic
type RetryManager struct {
	maxRetries      int
	baseDelay       time.Duration
	maxDelay        time.Duration
	backoffFactor   float64
	jitterFactor    float64
	mu              sync.RWMutex
	retryCounts     map[string]int
}

// NewRetryManager creates a new retry manager
func NewRetryManager(maxRetries int, baseDelay, maxDelay time.Duration) *RetryManager {
	return &RetryManager{
		maxRetries:    maxRetries,
		baseDelay:     baseDelay,
		maxDelay:      maxDelay,
		backoffFactor: 2.0,
		jitterFactor:  0.1,
		retryCounts:   make(map[string]int),
	}
}

// ShouldRetry determines if an operation should be retried
func (rm *RetryManager) ShouldRetry(operationID string, err error) bool {
	rm.mu.RLock()
	count := rm.retryCounts[operationID]
	rm.mu.RUnlock()
	
	if count >= rm.maxRetries {
		return false
	}
	
	// Check if error is retryable
	if mcpErr, ok := err.(*MCError); ok {
		return mcpErr.IsRetryable()
	}
	
	// Default: retry on connection-related errors
	errStr := err.Error()
	if containsAny(errStr, []string{"connection", "timeout", "network", "temporarily"}) {
		return true
	}
	
	return false
}

// GetRetryDelay calculates the retry delay with exponential backoff and jitter
func (rm *RetryManager) GetRetryDelay(operationID string) time.Duration {
	rm.mu.RLock()
	count := rm.retryCounts[operationID]
	rm.mu.RUnlock()
	
	// Calculate exponential backoff
	delay := rm.baseDelay
	for i := 0; i < count; i++ {
		delay = time.Duration(float64(delay) * rm.backoffFactor)
		if delay > rm.maxDelay {
			delay = rm.maxDelay
			break
		}
	}
	
	// Add jitter
	delay = addJitter(delay, rm.jitterFactor)
	
	return delay
}

// IncrementRetryCount increments the retry count for an operation
func (rm *RetryManager) IncrementRetryCount(operationID string) {
	rm.mu.Lock()
	rm.retryCounts[operationID]++
	rm.mu.Unlock()
}

// ResetRetryCount resets the retry count for an operation
func (rm *RetryManager) ResetRetryCount(operationID string) {
	rm.mu.Lock()
	delete(rm.retryCounts, operationID)
	rm.mu.Unlock()
}

// addJitter adds jitter to a duration
func addJitter(duration time.Duration, jitterFactor float64) time.Duration {
	jitter := float64(duration) * jitterFactor
	return duration + time.Duration(jitter*0.5) // 0.5 for symmetric jitter
}

// containsAny checks if a string contains any of the substrings
func containsAny(s string, substrings []string) bool {
	for _, substr := range substrings {
		if contains(s, substr) {
			return true
		}
	}
	return false
}

// contains checks if a string contains a substring (case-insensitive)
func contains(s, substr string) bool {
	// Simple implementation
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// ConnectionMonitor monitors connection health
type ConnectionMonitor struct {
	client        *CursorClient
	checkInterval time.Duration
	timeout       time.Duration
	maxFailures   int
	failureCount  int
	mu            sync.RWMutex
	running       bool
	stopCh        chan struct{}
}

// NewConnectionMonitor creates a new connection monitor
func NewConnectionMonitor(client *CursorClient, checkInterval, timeout time.Duration, maxFailures int) *ConnectionMonitor {
	return &ConnectionMonitor{
		client:        client,
		checkInterval: checkInterval,
		timeout:       timeout,
		maxFailures:   maxFailures,
		stopCh:        make(chan struct{}),
	}
}

// Start starts the connection monitor
func (cm *ConnectionMonitor) Start() {
	cm.mu.Lock()
	if cm.running {
		cm.mu.Unlock()
		return
	}
	cm.running = true
	cm.mu.Unlock()
	
	go cm.monitorLoop()
}

// Stop stops the connection monitor
func (cm *ConnectionMonitor) Stop() {
	cm.mu.Lock()
	if !cm.running {
		cm.mu.Unlock()
		return
	}
	cm.running = false
	cm.mu.Unlock()
	
	close(cm.stopCh)
}

// monitorLoop monitors the connection health
func (cm *ConnectionMonitor) monitorLoop() {
	ticker := time.NewTicker(cm.checkInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-cm.stopCh:
			return
		case <-ticker.C:
			cm.checkConnection()
		}
	}
}

// checkConnection checks the connection health
func (cm *ConnectionMonitor) checkConnection() {
	ctx, cancel := context.WithTimeout(context.Background(), cm.timeout)
	defer cancel()
	
	err := cm.client.HealthCheck(ctx)
	if err != nil {
		cm.mu.Lock()
		cm.failureCount++
		failureCount := cm.failureCount
		cm.mu.Unlock()
		
		log.Printf("Connection check failed (%d/%d): %v", failureCount, cm.maxFailures, err)
		
		if failureCount >= cm.maxFailures {
			log.Println("Max connection failures reached, attempting reconnect...")
			cm.reconnect()
		}
	} else {
		cm.mu.Lock()
		cm.failureCount = 0
		cm.mu.Unlock()
	}
}

// reconnect attempts to reconnect
func (cm *ConnectionMonitor) reconnect() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	
	if err := cm.client.Reconnect(ctx); err != nil {
		log.Printf("Reconnect failed: %v", err)
	} else {
		log.Println("Reconnect successful")
		cm.mu.Lock()
		cm.failureCount = 0
		cm.mu.Unlock()
	}
}

// ErrorHandler handles errors with appropriate actions
type ErrorHandler struct {
	retryManager      *RetryManager
	connectionMonitor *ConnectionMonitor
	logger            *log.Logger
}

// NewErrorHandler creates a new error handler
func NewErrorHandler(client *CursorClient) *ErrorHandler {
	retryManager := NewRetryManager(5, 1*time.Second, 30*time.Second)
	connectionMonitor := NewConnectionMonitor(client, 30*time.Second, 10*time.Second, 3)
	
	return &ErrorHandler{
		retryManager:      retryManager,
		connectionMonitor: connectionMonitor,
		logger:            log.Default(),
	}
}

// HandleError handles an error with appropriate action
func (eh *ErrorHandler) HandleError(operationID string, err error) error {
	if err == nil {
		eh.retryManager.ResetRetryCount(operationID)
		return nil
	}
	
	// Log error
	eh.logger.Printf("Error in operation %s: %v", operationID, err)
	
	// Check if should retry
	if eh.retryManager.ShouldRetry(operationID, err) {
		delay := eh.retryManager.GetRetryDelay(operationID)
		eh.retryManager.IncrementRetryCount(operationID)
		
		eh.logger.Printf("Will retry operation %s after %v (attempt %d)", 
			operationID, delay, eh.retryManager.retryCounts[operationID])
		
		// Return error with retry information
		return NewErrorWithRetry(ErrorRequestFailed, 
			fmt.Sprintf("Operation failed, will retry after %v", delay),
			err.Error(), delay)
	}
	
	// Not retryable or max retries reached
	eh.logger.Printf("Operation %s failed permanently: %v", operationID, err)
	return err
}

// StartMonitoring starts connection monitoring
func (eh *ErrorHandler) StartMonitoring() {
	eh.connectionMonitor.Start()
}

// StopMonitoring stops connection monitoring
func (eh *ErrorHandler) StopMonitoring() {
	eh.connectionMonitor.Stop()
}

// WrapOperation wraps an operation with error handling
func (eh *ErrorHandler) WrapOperation(operationID string, fn func() error) error {
	for {
		err := fn()
		handledErr := eh.HandleError(operationID, err)
		
		if handledErr == nil {
			return nil
		}
		
		// Check if we should retry
		if mcpErr, ok := handledErr.(*MCError); ok && mcpErr.RetryAfter != nil {
			// Wait before retrying
			time.Sleep(*mcpErr.RetryAfter)
			continue
		}
		
		// Permanent error
		return handledErr
	}
}