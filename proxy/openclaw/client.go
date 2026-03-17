package openclaw

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

// Client manages the WebSocket connection to the OpenClaw Gateway
type Client struct {
	config      *Config
	conn        *websocket.Conn
	mu          sync.Mutex
	reqID       atomic.Int64
	done        chan struct{}
	privateKey  ed25519.PrivateKey
	publicKey   ed25519.PublicKey
	deviceToken string

	// Event handlers
	OnTaskEvent      func(TaskPush)
	OnChatEvent      func(ChatEventPayload)
	OnStreamEvent    func(string, string) // commandID, delta
	OnStreamComplete func()               // lifecycle phase "end" or "error"
	OnHistoryEvent   func([]byte)         // history payload
	OnConnected      func()
	OnDisconnected   func(error)

	// Pending requests map reqID -> method
	pendingReqs map[string]string
	reqsMu      sync.RWMutex
}

// NewClient creates a new OpenClaw Gateway client
func NewClient(config *Config) *Client {
	c := &Client{
		config:      config,
		done:        make(chan struct{}),
		pendingReqs: make(map[string]string),
	}
	// Load or generate ED25519 keypair
	c.loadOrGenerateKeypair()
	// Try to load persisted device token
	c.deviceToken = c.loadDeviceToken()
	return c
}

// buildOriginFromGatewayURL returns an Origin header value (e.g. http://127.0.0.1:18789)
// so the gateway's origin check accepts the connection instead of "origin-mismatch".
func buildOriginFromGatewayURL(gatewayURL string) string {
	u, err := url.Parse(gatewayURL)
	if err != nil {
		return "http://127.0.0.1:18789"
	}
	scheme := "http"
	if u.Scheme == "wss" {
		scheme = "https"
	}
	host := u.Host
	if host == "" {
		host = "127.0.0.1:18789"
	}
	return scheme + "://" + host
}

// Connect establishes the WebSocket connection and performs handshake
func (c *Client) Connect() error {
	if err := c.config.Validate(); err != nil {
		return err
	}

	log.Printf("[OpenClaw] Connecting to Gateway: %s", c.config.GatewayURL)

	// Gateway requires a valid Origin or rejects with "origin-mismatch" / "origin missing or invalid"
	headers := http.Header{}
	originURL := buildOriginFromGatewayURL(c.config.GatewayURL)
	headers.Set("Origin", originURL)

	conn, _, err := websocket.DefaultDialer.Dial(c.config.GatewayURL, headers)
	if err != nil {
		return fmt.Errorf("openclaw: failed to connect to gateway: %w", err)
	}

	c.mu.Lock()
	c.conn = conn
	c.mu.Unlock()

	// Perform handshake
	if err := c.handshake(); err != nil {
		conn.Close()
		return fmt.Errorf("openclaw: handshake failed: %w", err)
	}

	log.Printf("[OpenClaw] Connected to Gateway successfully")

	if c.OnConnected != nil {
		c.OnConnected()
	}

	return nil
}

// Start connects and begins listening for events. Handles auto-reconnect.
func (c *Client) Start() {
	go func() {
		for {
			select {
			case <-c.done:
				return
			default:
			}

			err := c.Connect()
			if err != nil {
				log.Printf("[OpenClaw] Connection error: %v", err)
				if !c.config.AutoReconnect {
					return
				}
				log.Printf("[OpenClaw] Reconnecting in %ds...", c.config.ReconnectIntervalSec)
				time.Sleep(time.Duration(c.config.ReconnectIntervalSec) * time.Second)
				continue
			}

			// Listen for events (blocks until disconnection)
			err = c.listenEvents()
			if err != nil {
				log.Printf("[OpenClaw] Disconnected: %v", err)
			}

			if c.OnDisconnected != nil {
				c.OnDisconnected(err)
			}

			if !c.config.AutoReconnect {
				return
			}

			log.Printf("[OpenClaw] Reconnecting in %ds...", c.config.ReconnectIntervalSec)
			time.Sleep(time.Duration(c.config.ReconnectIntervalSec) * time.Second)
		}
	}()
}

// Stop gracefully closes the connection
func (c *Client) Stop() {
	close(c.done)
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn != nil {
		c.conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
		c.conn.Close()
		c.conn = nil
	}
}

// SendTask sends a chat message to the OpenClaw Agent.
// The prompt should already include any skill context prepended by the caller.
func (c *Client) SendTask(prompt, priority string) (string, error) {
	reqID := c.nextID()
	params := ChatSendParams{
		SessionKey:     "agent:main:main",
		Message:        prompt,
		IdempotencyKey: reqID,
		TimeoutMs:      30000,
		Thinking:       "auto",
	}

	paramsJSON, err := json.Marshal(params)
	if err != nil {
		return "", err
	}

	frame := Frame{
		Type:   "req",
		ID:     reqID,
		Method: "chat.send",
		Params: paramsJSON,
	}

	if err := c.writeJSON(frame); err != nil {
		return "", fmt.Errorf("openclaw: failed to send chat: %w", err)
	}

	log.Printf("[OpenClaw] Sent chat request %s: %s", reqID, prompt)
	return reqID, nil
}

// ChatHistory retrieves the chat history for the main session
func (c *Client) ChatHistory(limit int) error {
	reqID := c.nextID()
	params := ChatHistoryParams{
		SessionKey: "agent:main:main",
		Limit:      limit,
	}

	paramsJSON, err := json.Marshal(params)
	if err != nil {
		return err
	}

	frame := Frame{
		Type:   "req",
		ID:     reqID,
		Method: "chat.history",
		Params: paramsJSON,
	}

	if err := c.writeJSON(frame); err != nil {
		return fmt.Errorf("openclaw: failed to request chat history: %w", err)
	}

	log.Printf("[OpenClaw] Sent chat history request %s", reqID)
	return nil
}

// ChatAbort requests the gateway to abort an ongoing run in the main session
func (c *Client) ChatAbort(runID string) error {
	reqID := c.nextID()
	params := ChatAbortParams{
		SessionKey: "main",
		RunID:      runID,
	}

	paramsJSON, err := json.Marshal(params)
	if err != nil {
		return err
	}

	frame := Frame{
		Type:   "req",
		ID:     reqID,
		Method: "chat.abort",
		Params: paramsJSON,
	}

	if err := c.writeJSON(frame); err != nil {
		return fmt.Errorf("openclaw: failed to abort chat run: %w", err)
	}

	log.Printf("[OpenClaw] Sent chat abort request %s for run %s", reqID, runID)
	return nil
}

// SyncSession requests the gateway to sync a given session
func (c *Client) SyncSession(sessionKey string) error {
	reqID := c.nextID()
	params := map[string]interface{}{
		"sessionKey": sessionKey,
	}

	paramsJSON, err := json.Marshal(params)
	if err != nil {
		return err
	}

	frame := Frame{
		Type:   "req",
		ID:     reqID,
		Method: "sessions.sync",
		Params: paramsJSON, // Fixed syntax here (struct vs var) originally, now just json.RawMessage
	}

	if err := c.writeJSON(frame); err != nil {
		return fmt.Errorf("openclaw: failed to sync session: %w", err)
	}

	log.Printf("[OpenClaw] Sent sessions.sync request %s for %s", reqID, sessionKey)
	return nil
}

// IsConnected returns whether the client is currently connected
func (c *Client) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.conn != nil
}

// ---- Internal methods ----

func (c *Client) handshake() error {
	// Step 1: Read the connect.challenge event from Gateway
	_, data, err := c.conn.ReadMessage()
	if err != nil {
		return fmt.Errorf("failed to read challenge: %w", err)
	}

	log.Printf("[OpenClaw] Received challenge: %s", string(data))

	// Parse challenge event
	var challengeEvent struct {
		Type    string `json:"type"`
		Event   string `json:"event"`
		Payload struct {
			Nonce string `json:"nonce"`
			Ts    int64  `json:"ts"`
		} `json:"payload"`
	}

	if err := json.Unmarshal(data, &challengeEvent); err != nil {
		return fmt.Errorf("failed to parse challenge: %w", err)
	}

	if challengeEvent.Event != "connect.challenge" {
		return fmt.Errorf("expected connect.challenge, got: %s", challengeEvent.Event)
	}

	nonce := challengeEvent.Payload.Nonce
	signedAtMs := time.Now().UnixMilli()
	log.Printf("[OpenClaw] Signing nonce: %s", nonce)

	// Step 2: Build device identity
	// deviceId = SHA256(publicKey) as hex (matches OpenClaw convention)
	pubKeyHash := sha256.Sum256(c.publicKey)
	deviceID := hex.EncodeToString(pubKeyHash[:])
	// publicKey = base64url encoded without padding
	pubKeyB64 := base64.RawURLEncoding.EncodeToString(c.publicKey)

	clientID := "cli"
	clientMode := "cli"
	role := "operator"
	scopes := []string{"operator.admin", "operator.approvals", "operator.pairing"}
	scopesStr := "operator.admin,operator.approvals,operator.pairing"

	// Step 3: Build signed payload matching OpenClaw's buildDeviceAuthPayload
	// Format: v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
	payload := fmt.Sprintf("v2|%s|%s|%s|%s|%s|%d|%s|%s",
		deviceID, clientID, clientMode, role, scopesStr,
		signedAtMs, c.config.Token, nonce)

	log.Printf("[OpenClaw] Signing payload: %s", payload)
	signature := c.signPayload(payload)

	// Step 4: Send connect request
	connectParams := ConnectParams{
		MinProtocol: 3,
		MaxProtocol: 3,
		Client: ConnectClient{
			ID:       clientID,
			Version:  c.config.ClientVersion,
			Platform: "darwin",
			Mode:     clientMode,
		},
		Role:        role,
		Scopes:      scopes,
		Caps:        []string{},
		Commands:    []string{},
		Permissions: map[string]bool{},
		Auth: ConnectAuth{
			Token:       c.config.Token,
			DeviceToken: c.deviceToken,
		},
		Locale:    "en-US",
		UserAgent: fmt.Sprintf("xassistant/%s", c.config.ClientVersion),
		Device: &DeviceInfo{
			ID:        deviceID,
			PublicKey: pubKeyB64,
			Nonce:     nonce,
			Signature: signature,
			SignedAt:  signedAtMs,
		},
	}

	paramsJSON, err := json.Marshal(connectParams)
	if err != nil {
		return err
	}

	frame := Frame{
		Type:   "req",
		ID:     c.nextID(),
		Method: "connect",
		Params: paramsJSON,
	}

	if err := c.writeJSON(frame); err != nil {
		return fmt.Errorf("failed to send connect frame: %w", err)
	}

	// Step 5: Read connect response
	_, data, err = c.conn.ReadMessage()
	if err != nil {
		return fmt.Errorf("failed to read connect response: %w", err)
	}

	log.Printf("[OpenClaw] Connect response: %s", string(data))

	var resp Response
	if err := json.Unmarshal(data, &resp); err != nil {
		return fmt.Errorf("failed to parse connect response (raw: %s): %w", string(data), err)
	}

	if !resp.OK {
		errMsg := "unknown error"
		if resp.Error != nil {
			errMsg = resp.Error.Message
		}
		if errMsg == "unknown error" && resp.Payload != nil {
			errMsg = fmt.Sprintf("payload: %s", string(resp.Payload))
		}
		return fmt.Errorf("connect rejected: %s", errMsg)
	}

	// Parse and persist device token
	var connectResp ConnectResponse
	if resp.Payload != nil {
		if err := json.Unmarshal(resp.Payload, &connectResp); err == nil {
			if connectResp.DeviceToken != "" {
				c.deviceToken = connectResp.DeviceToken
				c.saveDeviceToken(connectResp.DeviceToken)
			}
			log.Printf("[OpenClaw] Session established: %s", connectResp.SessionID)
		}
	}

	return nil
}

// signPayload signs the full payload string with the ED25519 private key (base64url encoded)
func (c *Client) signPayload(payload string) string {
	sig := ed25519.Sign(c.privateKey, []byte(payload))
	return base64.RawURLEncoding.EncodeToString(sig)
}

// openclawDeviceJSON represents the device.json file from OpenClaw
type openclawDeviceJSON struct {
	DeviceID      string `json:"deviceId"`
	PublicKeyPem  string `json:"publicKeyPem"`
	PrivateKeyPem string `json:"privateKeyPem"`
}

// loadOrGenerateKeypair tries to load OpenClaw's existing device identity first,
// then falls back to generating a new keypair
func (c *Client) loadOrGenerateKeypair() {
	// Strategy 1: Load from OpenClaw's device.json (already trusted by Gateway)
	homeDir, _ := os.UserHomeDir()
	openclawDevicePath := filepath.Join(homeDir, ".openclaw", "identity", "device.json")

	data, err := os.ReadFile(openclawDevicePath)
	if err == nil {
		var device openclawDeviceJSON
		if err := json.Unmarshal(data, &device); err == nil {
			privKey, pubKey, err := parsePEMKeypair(device.PrivateKeyPem, device.PublicKeyPem)
			if err == nil {
				c.privateKey = privKey
				c.publicKey = pubKey
				log.Printf("[OpenClaw] Loaded existing device identity from %s (id: %s...)", openclawDevicePath, device.DeviceID[:16])
				return
			}
			log.Printf("[OpenClaw] Failed to parse OpenClaw device keys: %v", err)
		}
	}

	// Strategy 2: Load from our own persisted keypair
	keyDir := filepath.Dir(c.config.DeviceTokenPath)
	privKeyPath := filepath.Join(keyDir, "device_key")
	pubKeyPath := filepath.Join(keyDir, "device_key.pub")

	privData, err := os.ReadFile(privKeyPath)
	if err == nil {
		pubData, err2 := os.ReadFile(pubKeyPath)
		if err2 == nil {
			privKey, err3 := hex.DecodeString(string(privData))
			pubKey, err4 := hex.DecodeString(string(pubData))
			if err3 == nil && err4 == nil && len(privKey) == ed25519.PrivateKeySize {
				c.privateKey = ed25519.PrivateKey(privKey)
				c.publicKey = ed25519.PublicKey(pubKey)
				log.Printf("[OpenClaw] Loaded device keypair from %s", keyDir)
				return
			}
		}
	}

	// Strategy 3: Generate new keypair
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		log.Printf("[OpenClaw] Failed to generate keypair: %v", err)
		return
	}

	c.privateKey = priv
	c.publicKey = pub

	// Persist keypair
	if err := os.MkdirAll(keyDir, 0700); err != nil {
		log.Printf("[OpenClaw] Failed to create key directory %s: %v", keyDir, err)
		return
	}
	if err := os.WriteFile(privKeyPath, []byte(hex.EncodeToString(priv)), 0600); err != nil {
		log.Printf("[OpenClaw] Failed to write private key: %v", err)
	}
	if err := os.WriteFile(pubKeyPath, []byte(hex.EncodeToString(pub)), 0644); err != nil {
		log.Printf("[OpenClaw] Failed to write public key: %v", err)
	}
	log.Printf("[OpenClaw] Generated new device keypair at %s", keyDir)
}

// parsePEMKeypair parses PEM-encoded ED25519 private and public keys
func parsePEMKeypair(privPEM, pubPEM string) (ed25519.PrivateKey, ed25519.PublicKey, error) {
	// Parse private key from PEM
	privBlock, _ := pem.Decode([]byte(privPEM))
	if privBlock == nil {
		return nil, nil, fmt.Errorf("failed to decode private key PEM")
	}

	privKeyParsed, err := x509.ParsePKCS8PrivateKey(privBlock.Bytes)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to parse private key: %w", err)
	}

	edPriv, ok := privKeyParsed.(ed25519.PrivateKey)
	if !ok {
		return nil, nil, fmt.Errorf("private key is not ED25519")
	}

	// Extract public key from private key
	edPub := edPriv.Public().(ed25519.PublicKey)

	return edPriv, edPub, nil
}

func (c *Client) listenEvents() error {
	for {
		select {
		case <-c.done:
			return nil
		default:
		}

		_, data, err := c.conn.ReadMessage()
		if err != nil {
			return err
		}

		c.handleFrame(data)
	}
}

func (c *Client) handleFrame(data []byte) {
	// Determine frame type
	var frame struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(data, &frame); err != nil {
		log.Printf("[OpenClaw] Invalid frame: %v", err)
		return
	}

	switch frame.Type {
	case "event":
		c.handleEvent(data)
	case "res":
		// Response to a previous request
		var resp Response
		if err := json.Unmarshal(data, &resp); err == nil {
			c.reqsMu.RLock()
			method := c.pendingReqs[resp.ID]
			c.reqsMu.RUnlock()

			if !resp.OK && resp.Error != nil {
				log.Printf("[OpenClaw] Request %s (%s) failed: %s", resp.ID, method, resp.Error.Message)
			} else if resp.OK {
				log.Printf("[OpenClaw] Request %s (%s) succeeded", resp.ID, method)
				if resp.Payload != nil {
					if method == "chat.history" {
						if c.OnHistoryEvent != nil {
							c.OnHistoryEvent(resp.Payload)
						}
					} else {
						// Output the payload only if it's NOT a massive chat history
						log.Printf("[OpenClaw] Payload: %s", string(resp.Payload))
					}
				}
			}

			// cleanup
			c.reqsMu.Lock()
			delete(c.pendingReqs, resp.ID)
			c.reqsMu.Unlock()
		}
	default:
		log.Printf("[OpenClaw] Unknown frame type: %s", frame.Type)
	}
}

func (c *Client) handleEvent(data []byte) {
	var event Event
	if err := json.Unmarshal(data, &event); err != nil {
		log.Printf("[OpenClaw] Failed to parse event: %v", err)
		return
	}

	switch event.EventName {
	case "agent":
		c.handleAgentEvent(event.Payload)

	case "chat":
		log.Printf("[OpenClaw] Chat event received: %s", string(event.Payload))
		var chatPayload ChatEventPayload
		if err := json.Unmarshal(event.Payload, &chatPayload); err == nil {
			if c.OnChatEvent != nil {
				c.OnChatEvent(chatPayload)
			}
		}

	case "heartbeat", "tick", "health", "presence":
		// Informational, log only
		log.Printf("[OpenClaw] Event: %s", event.EventName)

	default:
		log.Printf("[OpenClaw] Unhandled event: %s, payload: %s", event.EventName, string(event.Payload))
	}
}

func (c *Client) handleAgentEvent(payload json.RawMessage) {
	var agentEvent AgentEventPayload
	if err := json.Unmarshal(payload, &agentEvent); err != nil {
		log.Printf("[OpenClaw] Failed to parse agent event: %v, raw: %s", err, string(payload))
		return
	}

	// Handle streaming assistant chunks (V1 legacy string deltas)
	// We no longer send these to Flutter since V2 chat events provide cumulative text.
	// Sending these would overwrite the UI bubble with single-character deltas.
	/*
		if agentEvent.Stream == "assistant" && agentEvent.Data.Delta != "" {
			if c.OnStreamEvent != nil {
				c.OnStreamEvent("openclaw_chat", agentEvent.Data.Delta)
			}
			return
		}
	*/

	// Handle lifecycle: phase "end" or "error" = stream complete
	if agentEvent.Stream == "lifecycle" {
		phase := agentEvent.Data.Phase
		log.Printf("[OpenClaw] Lifecycle event: phase=%q", phase)
		if (phase == "end" || phase == "error") && c.OnStreamComplete != nil {
			c.OnStreamComplete()
		}
		return
	}

	// Handle stream errors
	if agentEvent.Stream == "error" {
		log.Printf("[OpenClaw] Agent stream error: %s", string(payload))

		// "seq gap" is a transient sync warning from OpenClaw, the backend usually
		// self-recovers and continues sending deltas shortly after. We do NOT want
		// to complete the UI stream bubble prematurely.
		if agentEvent.Data.Reason == "seq gap" {
			return
		}

		if c.OnStreamComplete != nil {
			c.OnStreamComplete()
		}
		return
	}

	// Log unhandled stream types for debugging
	if agentEvent.Stream != "" && agentEvent.Stream != "assistant" {
		log.Printf("[OpenClaw] Agent stream (unhandled): %q data=%s", agentEvent.Stream, string(payload))
	}

	// If no action, skip processing task payloads
	if agentEvent.Action == "" {
		return
	}

	log.Printf("[OpenClaw] Agent event: %s — %s. raw: %s", agentEvent.Action, agentEvent.Task.Title, string(payload))

	// Convert to TaskPush for Flutter
	taskPush := TaskPush{
		Type: "openclaw_task",
	}

	switch agentEvent.Action {
	case "task_start":
		taskPush.Action = "create"
		taskPush.Task = TaskData{
			ID:          agentEvent.Task.ID,
			Title:       agentEvent.Task.Title,
			Description: agentEvent.Task.Description,
			Priority:    "p1",
			Source:      "openClaw",
			Status:      "inProgress",
		}

	case "task_progress":
		taskPush.Action = "update"
		taskPush.Task = TaskData{
			ID:          agentEvent.Task.ID,
			Title:       agentEvent.Task.Title,
			Description: agentEvent.Task.Description,
			Priority:    "p1",
			Source:      "openClaw",
			Status:      "inProgress",
			Result:      agentEvent.Task.Result,
		}

	case "task_complete":
		taskPush.Action = "complete"
		taskPush.Task = TaskData{
			ID:          agentEvent.Task.ID,
			Title:       agentEvent.Task.Title,
			Description: agentEvent.Task.Description,
			Priority:    "p1",
			Source:      "openClaw",
			Status:      "completed",
			Result:      agentEvent.Task.Result,
		}

	case "task_error":
		taskPush.Action = "error"
		taskPush.Task = TaskData{
			ID:       agentEvent.Task.ID,
			Title:    agentEvent.Task.Title,
			Priority: "p1",
			Source:   "openClaw",
			Status:   "waitingFeedback",
			Feedback: agentEvent.Task.Error,
		}

	default:
		log.Printf("[OpenClaw] Unknown agent action: %s", agentEvent.Action)
		return
	}

	if c.OnTaskEvent != nil {
		c.OnTaskEvent(taskPush)
	}
}

// ---- Utility methods ----

func (c *Client) writeJSON(v interface{}) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn == nil {
		return fmt.Errorf("not connected")
	}

	// If this is a req frame, capture the method
	if frame, ok := v.(Frame); ok && frame.Type == "req" && frame.ID != "" {
		c.reqsMu.Lock()
		c.pendingReqs[frame.ID] = frame.Method
		c.reqsMu.Unlock()

		// Optional: cleanup pending requests after configured interval to avoid memory leak
		go func(id string) {
			time.Sleep(time.Duration(c.config.PendingRequestCleanupSec) * time.Second)
			c.reqsMu.Lock()
			delete(c.pendingReqs, id)
			c.reqsMu.Unlock()
		}(frame.ID)
	}

	return c.conn.WriteJSON(v)
}

func (c *Client) nextID() string {
	// Use a millisecond timestamp suffix to avoid RunID collisions with previous proxy instances,
	// which causes the Gateway to reuse old chat buffers and deduplicate requests.
	return fmt.Sprintf("xa-%d-%d", time.Now().UnixMilli()%1000000, c.reqID.Add(1))
}

func (c *Client) loadDeviceToken() string {
	data, err := os.ReadFile(c.config.DeviceTokenPath)
	if err != nil {
		return ""
	}
	return string(data)
}

func (c *Client) saveDeviceToken(token string) {
	dir := filepath.Dir(c.config.DeviceTokenPath)
	if err := os.MkdirAll(dir, 0700); err != nil {
		log.Printf("[OpenClaw] Failed to create token directory %s: %v", dir, err)
		return
	}
	if err := os.WriteFile(c.config.DeviceTokenPath, []byte(token), 0600); err != nil {
		log.Printf("[OpenClaw] Failed to save device token: %v", err)
	}
}
