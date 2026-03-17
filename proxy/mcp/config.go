package mcp

import (
	"fmt"
	"os"
	"path/filepath"
)

// Config holds MCP server configuration
type Config struct {
	// Transport configuration
	TransportType string `json:"transport_type"` // "stdio" or "http"
	HTTPPort      int    `json:"http_port"`      // Port for HTTP transport
	HTTPHost      string `json:"http_host"`      // Host for HTTP transport
	
	// Cursor connection
	CursorPath    string `json:"cursor_path"`    // Path to Cursor executable
	WorkspaceDir  string `json:"workspace_dir"`  // Workspace directory for Cursor
	
	// Session management
	SessionTimeout int `json:"session_timeout"` // Session timeout in seconds
	
	// Logging
	LogLevel string `json:"log_level"` // debug, info, warn, error
}

// DefaultConfig returns the default configuration
func DefaultConfig() *Config {
	wd, _ := os.Getwd()
	
	return &Config{
		TransportType:  "stdio",      // Default to stdio transport
		HTTPPort:       3000,         // Default HTTP port
		HTTPHost:       "localhost",  // Default HTTP host
		CursorPath:     "cursor",     // Assume cursor is in PATH
		WorkspaceDir:   wd,           // Current working directory
		SessionTimeout: 3600,         // 1 hour session timeout
		LogLevel:       "info",       // Default log level
	}
}

// Validate validates the configuration
func (c *Config) Validate() error {
	if c.TransportType != "stdio" && c.TransportType != "http" {
		return fmt.Errorf("invalid transport type: %s, must be 'stdio' or 'http'", c.TransportType)
	}
	
	if c.TransportType == "http" {
		if c.HTTPPort < 1 || c.HTTPPort > 65535 {
			return fmt.Errorf("invalid HTTP port: %d", c.HTTPPort)
		}
	}
	
	// Check if workspace directory exists
	if _, err := os.Stat(c.WorkspaceDir); os.IsNotExist(err) {
		return fmt.Errorf("workspace directory does not exist: %s", c.WorkspaceDir)
	}
	
	// Make workspace directory absolute
	absPath, err := filepath.Abs(c.WorkspaceDir)
	if err != nil {
		return fmt.Errorf("failed to get absolute path for workspace: %w", err)
	}
	c.WorkspaceDir = absPath
	
	return nil
}