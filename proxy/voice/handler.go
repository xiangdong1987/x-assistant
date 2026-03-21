package voice

import (
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin: func(r *http.Request) bool {
		return true // Caller is responsible for auth before reaching here
	},
}

// ServeVoiceWs upgrades the HTTP connection to WebSocket and runs the voice session.
// Auth (JWT token validation) must be performed by the caller before invoking this.
// hub and taskSender may be nil; voice still works for VAD+STT without AI.
func ServeVoiceWs(models *VoiceModels, hub HubCallbackRegistrar, taskSender DeviceAwareTaskSender, w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[Voice] WebSocket upgrade error: %v", err)
		return
	}

	session := newVoiceSession(conn, models)
	// Inject hub and taskSender so voice_start can build the Pipeline
	session.hub = hub
	session.taskSender = taskSender
	log.Printf("[Voice] new connection from %s", r.RemoteAddr)

	go session.writePump()
	go session.vadProcessor()
	go session.aiTtsWorker()
	session.readPump() // blocks until connection closes

	log.Printf("[Voice] connection closed: %s", r.RemoteAddr)
}
