package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"

	"claude-voice-proxy/auth"
	"claude-voice-proxy/mcp"
	"claude-voice-proxy/openclaw"
	"claude-voice-proxy/server"
)

// getEnvInt returns an integer value from environment variable with a default fallback
func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if intVal, err := strconv.Atoi(val); err == nil {
			return intVal
		}
		log.Printf("Warning: invalid value for %s: %s (using default: %d)", key, val, defaultVal)
	}
	return defaultVal
}

// getEnvString returns a string value from environment variable with a default fallback
func getEnvString(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func main() {
	// Parse command line flags
	port := flag.Int("port", 8443, "Server port")
	host := flag.String("host", "0.0.0.0", "Server host")
	workDir := flag.String("workdir", "", "Working directory for Claude Code")
	skillsPath := flag.String("skills-path", "", "Path to the skills directory (default: workdir/skills)")

	// MCP configuration flags
	mcpTransport := flag.String("mcp-transport", "stdio", "MCP transport type (stdio or http)")
	mcpCursorPath := flag.String("mcp-cursor-path", "cursor", "Path to Cursor executable")
	mcpHTTPPort := flag.Int("mcp-http-port", 3000, "MCP HTTP port (if using http transport)")
	mcpHTTPHost := flag.String("mcp-http-host", "localhost", "MCP HTTP host (if using http transport)")
	mcpSessionTimeout := flag.Int("mcp-session-timeout", 3600, "MCP session timeout in seconds")
	mcpLogLevel := flag.String("mcp-log-level", "info", "MCP log level (debug, info, warn, error)")

	// OpenClaw configuration flags
	openclawEnabled := flag.Bool("openclaw", false, "Enable OpenClaw Gateway integration")
	openclawURL := flag.String("openclaw-url", "", "OpenClaw Gateway WebSocket URL (env: OPENCLAW_GATEWAY_URL)")
	openclawToken := flag.String("openclaw-token", "", "OpenClaw Gateway token (env: OPENCLAW_GATEWAY_TOKEN)")
	openclawReconnect := flag.Int("openclaw-reconnect", 0, "OpenClaw reconnect interval in seconds (env: OPENCLAW_RECONNECT_INTERVAL)")
	openclawStreamIdle := flag.Int("openclaw-stream-idle", 0, "OpenClaw stream idle timeout in seconds (env: OPENCLAW_STREAM_IDLE)")
	openclawCleanup := flag.Int("openclaw-cleanup", 0, "OpenClaw pending request cleanup interval in seconds (env: OPENCLAW_CLEANUP_INTERVAL)")
	allowLocalNoAuth := flag.Bool("allow-local-no-auth", false, "Allow /api/tasks without JWT when request is from localhost (for skill scripts)")

	// Interval configuration flags
	taskSyncInterval := flag.Int("task-sync-interval", 0, "Task status sync interval in seconds (env: TASK_SYNC_INTERVAL)")
	phaseWatcherInterval := flag.Int("phase-watcher-interval", 0, "Phase watcher interval in seconds (env: PHASE_WATCHER_INTERVAL)")

	// Optional PIN to persist before start (for app-launch / launchd with known PIN so client can auto-connect)
	pinFlag := flag.String("pin", "", "Pairing PIN (6 digits); if set, persisted and used for this and future runs")
	// Log file: if set, all log output is written to this file (and still to stderr)
	logFile := flag.String("log", "", "Log file path; if set, logs are appended to this file for easier viewing")

	flag.Parse()

	// If -log provided, tee log output to the file
	if *logFile != "" {
		dir := filepath.Dir(*logFile)
		if err := os.MkdirAll(dir, 0755); err != nil {
			log.Printf("Warning: cannot create log dir %s: %v", dir, err)
		} else {
			f, err := os.OpenFile(*logFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
			if err != nil {
				log.Printf("Warning: cannot open log file %s: %v", *logFile, err)
			} else {
				defer f.Close()
				log.SetOutput(io.MultiWriter(os.Stderr, f))
				log.Printf("Logging to %s", *logFile)
			}
		}
	}

	// If -pin provided, persist it before server starts so PairingManager loads it
	if *pinFlag != "" {
		if err := auth.SavePIN(*pinFlag); err != nil {
			log.Fatalf("Invalid -pin: %v", err)
		}
		log.Printf("Using PIN from -pin flag (persisted)")
	}

	// Get working directory
	if *workDir == "" {
		wd, err := os.Getwd()
		if err != nil {
			log.Fatal("Failed to get working directory:", err)
		}
		*workDir = wd
	}

	// Create MCP configuration
	mcpConfig := &mcp.Config{
		TransportType:  *mcpTransport,
		HTTPPort:       *mcpHTTPPort,
		HTTPHost:       *mcpHTTPHost,
		CursorPath:     *mcpCursorPath,
		WorkspaceDir:   *workDir,
		SessionTimeout: *mcpSessionTimeout,
		LogLevel:       *mcpLogLevel,
	}

	// Validate MCP configuration
	if err := mcpConfig.Validate(); err != nil {
		log.Fatal("Invalid MCP configuration:", err)
	}

	// Create OpenClaw configuration
	openclawConfig := openclaw.DefaultConfig()
	openclawConfig.Enabled = *openclawEnabled

	// Apply configuration with priority: flag > env > default
	openclawConfig.GatewayURL = getEnvString("OPENCLAW_GATEWAY_URL", openclawConfig.GatewayURL)
	if *openclawURL != "" {
		openclawConfig.GatewayURL = *openclawURL
	}

	openclawConfig.Token = getEnvString("OPENCLAW_GATEWAY_TOKEN", openclawConfig.Token)
	if *openclawToken != "" {
		openclawConfig.Token = *openclawToken
	}

	openclawConfig.ReconnectIntervalSec = getEnvInt("OPENCLAW_RECONNECT_INTERVAL", openclawConfig.ReconnectIntervalSec)
	if *openclawReconnect != 0 {
		openclawConfig.ReconnectIntervalSec = *openclawReconnect
	}

	openclawConfig.StreamIdleCompleteSec = getEnvInt("OPENCLAW_STREAM_IDLE", openclawConfig.StreamIdleCompleteSec)
	if *openclawStreamIdle != 0 {
		openclawConfig.StreamIdleCompleteSec = *openclawStreamIdle
	}

	openclawConfig.PendingRequestCleanupSec = getEnvInt("OPENCLAW_CLEANUP_INTERVAL", openclawConfig.PendingRequestCleanupSec)
	if *openclawCleanup != 0 {
		openclawConfig.PendingRequestCleanupSec = *openclawCleanup
	}

	// Validate OpenClaw config if enabled
	if openclawConfig.Enabled {
		if err := openclawConfig.Validate(); err != nil {
			log.Fatal("Invalid OpenClaw configuration:", err)
		}
		log.Printf("OpenClaw integration enabled, Gateway: %s", openclawConfig.GatewayURL)
	}

	// Apply interval configurations with priority: flag > env > default
	taskSyncIntervalSec := getEnvInt("TASK_SYNC_INTERVAL", 5)
	if *taskSyncInterval != 0 {
		taskSyncIntervalSec = *taskSyncInterval
	}

	phaseWatcherIntervalSec := getEnvInt("PHASE_WATCHER_INTERVAL", 20)
	if *phaseWatcherInterval != 0 {
		phaseWatcherIntervalSec = *phaseWatcherInterval
	}

	// Create and start server
	srv := server.New(*host, *port, *workDir, *skillsPath, mcpConfig, openclawConfig, *allowLocalNoAuth, taskSyncIntervalSec, phaseWatcherIntervalSec)

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		fmt.Println("\nShutting down...")
		srv.Shutdown()
		os.Exit(0)
	}()

	// Start server
	if err := srv.Start(); err != nil {
		log.Fatal("Server error:", err)
	}
}
