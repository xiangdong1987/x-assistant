package openclaw

import (
	"fmt"
	"os"
	"path/filepath"
)

// Config holds the OpenClaw Gateway connection settings
type Config struct {
	// GatewayURL is the WebSocket URL of the OpenClaw Gateway
	// Default: ws://127.0.0.1:18789
	// Can be set via OPENCLAW_GATEWAY_URL env var or --openclaw-url flag
	GatewayURL string

	// Token is the Gateway authentication token
	// Can be set via OPENCLAW_GATEWAY_TOKEN env var or --openclaw-token flag
	Token string

	// DeviceTokenPath is the file path to persist the device token
	DeviceTokenPath string

	// ClientName identifies this client to the Gateway
	ClientName string

	// ClientVersion is the version string
	ClientVersion string

	// AutoReconnect enables automatic reconnection on disconnect
	AutoReconnect bool

	// ReconnectIntervalSec is the interval between reconnection attempts
	// Default: 5 seconds
	// Can be set via OPENCLAW_RECONNECT_INTERVAL env var or --openclaw-reconnect flag
	ReconnectIntervalSec int

	// StreamIdleCompleteSec is the timeout for stream idle before sending complete
	// Default: 300 seconds
	// Can be set via OPENCLAW_STREAM_IDLE env var or --openclaw-stream-idle flag
	StreamIdleCompleteSec int

	// PendingRequestCleanupSec is the cleanup interval for pending requests
	// Default: 30 seconds
	// Can be set via OPENCLAW_CLEANUP_INTERVAL env var or --openclaw-cleanup flag
	PendingRequestCleanupSec int

	// Enabled controls whether OpenClaw integration is active
	Enabled bool
}

// DefaultConfig returns a Config with sensible defaults
func DefaultConfig() *Config {
	homeDir, _ := os.UserHomeDir()
	return &Config{
		GatewayURL:             "ws://127.0.0.1:18789",
		Token:                  os.Getenv("OPENCLAW_GATEWAY_TOKEN"),
		DeviceTokenPath:        filepath.Join(homeDir, ".xassistant", "openclaw_device_token"),
		ClientName:             "xassistant",
		ClientVersion:          "1.0.0",
		AutoReconnect:          true,
		ReconnectIntervalSec:   5,
		StreamIdleCompleteSec:  300,
		PendingRequestCleanupSec: 30,
		Enabled:                false,
	}
}

// Validate checks that the config is valid for connection
func (c *Config) Validate() error {
	if c.GatewayURL == "" {
		return fmt.Errorf("openclaw: gateway URL is required")
	}
	if c.Token == "" {
		return fmt.Errorf("openclaw: gateway token is required (set OPENCLAW_GATEWAY_TOKEN or --openclaw-token)")
	}
	return nil
}
