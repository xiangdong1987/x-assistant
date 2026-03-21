package websocket

import (
	"log"
	"sync"
)

// Hub maintains the set of active clients and broadcasts messages
type Hub struct {
	// Registered clients
	clients map[*Client]bool

	// Register requests from clients
	register chan *Client

	// Unregister requests from clients
	unregister chan *Client

	// Mutex for thread-safe operations
	mu sync.RWMutex

	// deviceCallbacks allows non-Hub consumers (e.g. voice sessions) to receive
	// messages targeted at a specific deviceID without being registered as a Client.
	deviceCallbacks   map[string]func([]byte)
	deviceCallbacksMu sync.RWMutex
}

func NewHub() *Hub {
	return &Hub{
		clients:         make(map[*Client]bool),
		register:        make(chan *Client),
		unregister:      make(chan *Client),
		deviceCallbacks: make(map[string]func([]byte)),
	}
}

// RegisterDeviceCallback registers a callback to receive messages for deviceID.
// Used by voice sessions to intercept AI responses without entering the Hub client list.
func (h *Hub) RegisterDeviceCallback(deviceID string, fn func([]byte)) {
	h.deviceCallbacksMu.Lock()
	h.deviceCallbacks[deviceID] = fn
	h.deviceCallbacksMu.Unlock()
}

// UnregisterDeviceCallback removes the callback for deviceID.
func (h *Hub) UnregisterDeviceCallback(deviceID string) {
	h.deviceCallbacksMu.Lock()
	delete(h.deviceCallbacks, deviceID)
	h.deviceCallbacksMu.Unlock()
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			log.Printf("Client connected: %s", client.deviceID)

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.send)
			}
			h.mu.Unlock()
			log.Printf("Client disconnected: %s", client.deviceID)
		}
	}
}

// GetClient returns a client by device ID
func (h *Hub) GetClient(deviceID string) *Client {
	h.mu.RLock()
	defer h.mu.RUnlock()

	for client := range h.clients {
		if client.deviceID == deviceID {
			return client
		}
	}
	return nil
}

// ClientCount returns the number of connected clients
func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// Broadcast sends a message to all connected clients
func (h *Hub) Broadcast(data []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for client := range h.clients {
		select {
		case client.send <- data:
		default:
			log.Printf("[Hub] Dropped broadcast message for client %s: buffer full", client.deviceID)
		}
	}
}

// SendToDevice sends a message only to the client with the given device ID.
// Used for conversation thread isolation: responses go only to the requesting device.
// If no Hub client matches, falls back to a registered device callback (e.g. voice session).
func (h *Hub) SendToDevice(deviceID string, data []byte) {
	h.mu.RLock()
	for client := range h.clients {
		if client.deviceID == deviceID {
			select {
			case client.send <- data:
			default:
				log.Printf("[Hub] Dropped targeted message for device %s: buffer full", deviceID)
			}
			h.mu.RUnlock()
			return
		}
	}
	h.mu.RUnlock()

	// Fall back to device callback (non-Hub consumers such as voice sessions)
	h.deviceCallbacksMu.RLock()
	cb := h.deviceCallbacks[deviceID]
	h.deviceCallbacksMu.RUnlock()
	if cb != nil {
		cb(data)
	}
}
