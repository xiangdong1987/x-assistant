package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"claude-voice-proxy/auth"
	"claude-voice-proxy/mcp"
	"claude-voice-proxy/openclaw"
	"claude-voice-proxy/projects"
	"claude-voice-proxy/skills"
	"claude-voice-proxy/tasks"
	"claude-voice-proxy/voice"
	"claude-voice-proxy/websocket"

	qrcode "github.com/skip2/go-qrcode"
)

type Server struct {
	host             string
	port             int
	workDir          string
	skillsPath       string
	mcpConfig        *mcp.Config
	httpServer       *http.Server
	hub              *websocket.Hub
	pairing          *auth.PairingManager
	openclawConfig   *openclaw.Config
	openclawClient   *openclaw.Client
	openclawBridge   *openclaw.TaskBridge
	taskStore        *tasks.Store
	taskHandlers     *tasks.Handlers
	chatHistoryStore *tasks.ChatHistoryStore
	skillManager     *skills.Manager
	projectRegistry  *projects.Registry
	allowLocalNoAuth bool
	ctx              context.Context
	cancelCtx        context.CancelFunc
	// 保证长时间任务不因客户端断开而中断：auto-execute/phase-pipeline 后台执行
	runningPipelines   map[string]bool
	runningPipelinesMu sync.Mutex
	// Interval configurations
	taskSyncInterval     time.Duration
	phaseWatcherInterval time.Duration
	// Voice pipeline (nil when disabled)
	voiceModels *voice.VoiceModels
}

func New(host string, port int, workDir string, skillsPath string, mcpConfig *mcp.Config, openclawConfig *openclaw.Config, allowLocalNoAuth bool, taskSyncInterval int, phaseWatcherInterval int, voiceConfig *voice.VoiceConfig) *Server {
	hub := websocket.NewHub()
	runningPipelines := make(map[string]bool)

	s := &Server{
		host:             host,
		port:             port,
		workDir:          workDir,
		skillsPath:       skillsPath,
		mcpConfig:        mcpConfig,
		hub:              hub,
		pairing:          auth.NewPairingManager(),
		openclawConfig:   openclawConfig,
		allowLocalNoAuth: allowLocalNoAuth,
		runningPipelines: runningPipelines,
		taskSyncInterval:   time.Duration(taskSyncInterval) * time.Second,
		phaseWatcherInterval: time.Duration(phaseWatcherInterval) * time.Second,
	}

	// Initialize task store
	if store, err := tasks.NewStore(workDir); err != nil {
		log.Printf("Warning: task store init failed: %v (tasks API disabled)", err)
	} else {
		s.taskStore = store
		s.taskHandlers = &tasks.Handlers{
			Store: store,
			OnTaskUpdate: func(action string, task *tasks.Task) {
				msg := map[string]interface{}{
					"type":   "openclaw_task",
					"action": action,
					"task":   task,
				}
				if data, err := json.Marshal(msg); err == nil {
					hub.Broadcast(data)
				}
			},
		}
	}

	// Initialize skill manager
	s.skillManager = skills.NewManager(workDir)
	// Auto-seed skill paths from -skills-path flag (or workDir/skills) when config is empty
	if existing, err := s.skillManager.GetPaths(); err == nil && len(existing) == 0 {
		seedPath := skillsPath
		if seedPath == "" {
			seedPath = filepath.Join(workDir, "skills")
		}
		if err := s.skillManager.SetPaths([]string{seedPath}); err != nil {
			log.Printf("[Skills] Warning: failed to auto-seed skill paths: %v", err)
		} else {
			log.Printf("[Skills] Auto-seeded skill paths: [%s]", seedPath)
		}
	}

	// Initialize chat history store
	if chatStore, err := tasks.NewChatHistoryStore(workDir); err != nil {
		log.Printf("Warning: chat history store init failed: %v", err)
	} else {
		s.chatHistoryStore = chatStore
		log.Printf("Chat history store initialized at %s", filepath.Join(workDir, "data", "chat_history.json"))
	}

	// Initialize project registry
	s.projectRegistry = projects.NewRegistry(workDir)

	// Initialize OpenClaw client if enabled
	if openclawConfig != nil && openclawConfig.Enabled {
		s.openclawClient = openclaw.NewClient(openclawConfig)
		s.openclawBridge = openclaw.NewTaskBridge(hub, s.openclawClient, s.taskStore, s.skillManager, skillsPath)
	}

	// Initialize voice pipeline if enabled (failure is non-fatal)
	if voiceConfig != nil && voiceConfig.Enabled {
		if m, err := voice.NewVoiceModels(voiceConfig); err != nil {
			log.Printf("[Voice] model init failed: %v (voice disabled)", err)
		} else {
			s.voiceModels = m
			log.Printf("[Voice] pipeline ready (VAD=%v STT=%v TTS=%v)",
				m.HasVAD(), m.HasSTT(), m.HasTTS())
		}
	}

	return s
}

func (s *Server) Start() error {
	ctx, cancel := context.WithCancel(context.Background())
	s.ctx = ctx
	s.cancelCtx = cancel

	// Start background task status sync
	if s.taskStore != nil && s.taskHandlers != nil {
		go func() {
			ticker := time.NewTicker(s.taskSyncInterval)
			defer ticker.Stop()
			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					s.taskStore.SyncTaskStatus(s.taskHandlers.OnTaskUpdate)
				}
			}
		}()
		// 触发式阶段执行：定时分析 plan/任务状态，对「当前阶段已终态」的任务触发下一阶段
		go s.runPhaseWatcher()
	}

	// Start WebSocket hub
	go s.hub.Run()

	// Start OpenClaw client if configured
	if s.openclawClient != nil {
		log.Println("Starting OpenClaw Gateway connection...")
		s.openclawClient.Start()
	}

	// Setup routes
	mux := http.NewServeMux()
	mux.HandleFunc("/api/health", s.handleHealth)
	mux.HandleFunc("/api/shutdown", s.handleShutdown)
	mux.HandleFunc("/api/pair", s.handlePair)
	mux.HandleFunc("/api/pair/info", s.handlePairInfo)
	mux.HandleFunc("/api/pair/reset", s.handlePairReset)
	mux.HandleFunc("/api/openclaw/status", s.handleOpenClawStatus)
	mux.HandleFunc("/api/openclaw/task", s.handleOpenClawSendTask)
	mux.HandleFunc("/api/config/skill-paths", s.handleSkillPaths)
	mux.HandleFunc("/api/skills/execute", s.handleSkillExecute)
	mux.HandleFunc("/api/skills/", s.handleSkillsAPI)
	mux.HandleFunc("/api/skills", s.handleSkillsAPI)
	mux.HandleFunc("/api/projects/", s.handleProjectAPI)
	mux.HandleFunc("/api/projects", s.handleProjectAPI)
	mux.HandleFunc("/api/capabilities/execute", s.handleCapabilityExecute)
	if s.taskHandlers != nil {
		mux.HandleFunc("/api/tasks", s.handleTasksAPI)
		mux.HandleFunc("/api/tasks/", s.handleTaskByIDAPI)
	}
	if s.chatHistoryStore != nil {
		mux.HandleFunc("/api/chat-history", s.handleChatHistoryAPI)
	}
	mux.HandleFunc("/ws", s.handleWebSocket)
	mux.HandleFunc("/api/voice/status", s.handleVoiceStatus)
	mux.HandleFunc("/voice/ws", s.handleVoiceWebSocket) // handler returns 503 when models not loaded
	mux.HandleFunc("/voice-test", s.handleVoiceTestPage)

	// Create HTTP server
	addr := fmt.Sprintf("%s:%d", s.host, s.port)
	s.httpServer = &http.Server{
		Addr:         addr,
		Handler:      corsMiddleware(mux),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
	}

	// Get local IP
	localIP := getLocalIP()

	// Generate and display pairing info
	s.displayPairingInfo(localIP)

	log.Printf("Server starting on %s", addr)
	log.Printf("Working directory: %s", s.workDir)

	return s.httpServer.ListenAndServe()
}

func (s *Server) Shutdown() {
	if s.cancelCtx != nil {
		s.cancelCtx()
	}

	// Stop OpenClaw client
	if s.openclawClient != nil {
		s.openclawClient.Stop()
	}

	// Close voice models
	if s.voiceModels != nil {
		s.voiceModels.Close()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	s.httpServer.Shutdown(ctx)
}

func (s *Server) displayPairingInfo(ip string) {
	pin := s.pairing.GeneratePIN()
	pairURL := fmt.Sprintf("claude-voice://pair?ip=%s&port=%d&pin=%s", ip, s.port, pin)

	fmt.Println("\n" + string(repeat('=', 50)))
	fmt.Println("  Claude Voice Proxy - Ready for pairing")
	fmt.Println(string(repeat('=', 50)))
	fmt.Printf("\n  IP Address: %s\n", ip)
	fmt.Printf("  Port: %d\n", s.port)
	fmt.Printf("  PIN Code: %s\n", pin)
	fmt.Println("\n  Scan this QR code with Claude Voice app:")
	fmt.Println()

	// Generate QR code for terminal
	qr, err := qrcode.New(pairURL, qrcode.Medium)
	if err == nil {
		fmt.Println(qr.ToSmallString(false))
	}

	fmt.Println(string(repeat('=', 50)))
	fmt.Println("  Or enter manually in the app:")
	fmt.Printf("  IP: %s  PIN: %s\n", ip, pin)
	fmt.Println(string(repeat('=', 50)) + "\n")
}

// taskAPIURLHost returns host for TASK_API_URL when spawning scripts (curl must reach the proxy).
// Use 127.0.0.1 when server binds to 0.0.0.0 so scripts on same machine can PUT status.
func (s *Server) taskAPIURLHost() string {
	h := s.host
	if h == "" || h == "0.0.0.0" {
		return "127.0.0.1"
	}
	return h
}

// HTTP Handlers

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	health := map[string]interface{}{
		"status":  "ok",
		"version": "1.0.0",
		"workDir": s.workDir,
	}
	if s.taskStore != nil {
		health["taskStore"] = "ok"
	} else {
		health["taskStore"] = "unavailable"
	}
	if s.openclawClient != nil {
		health["openclawConnected"] = s.openclawClient.IsConnected()
	}
	health["wsClients"] = s.hub.ClientCount()
	json.NewEncoder(w).Encode(health)
}

func (s *Server) handleShutdown(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	token := r.URL.Query().Get("token")
	if token == "" {
		if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
			token = strings.TrimPrefix(h, "Bearer ")
		}
	}
	if token == "" {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "token required"})
		return
	}
	if _, err := auth.ValidateToken(token); err != nil {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "invalid token"})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"ok": true})
	go func() {
		time.Sleep(200 * time.Millisecond)
		s.Shutdown()
		os.Exit(0)
	}()
}

func (s *Server) handlePairInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	ip := getLocalIP()
	pin := s.pairing.GetCurrentPIN()

	json.NewEncoder(w).Encode(map[string]interface{}{
		"ip":   ip,
		"port": s.port,
		"pin":  pin,
	})
}

func (s *Server) handlePairReset(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Require JWT authentication for PIN reset
	token := r.URL.Query().Get("token")
	if token == "" {
		if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
			token = strings.TrimPrefix(h, "Bearer ")
		}
	}
	if token == "" {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "token required"})
		return
	}
	if _, err := auth.ValidateToken(token); err != nil {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "invalid token"})
		return
	}

	newPin := s.pairing.ResetPIN()
	ip := getLocalIP()

	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"pin":     newPin,
		"ip":      ip,
		"port":    s.port,
	})
	log.Printf("PIN reset requested, new PIN: %s", newPin)
}

func (s *Server) handlePair(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		PIN        string `json:"pin"`
		DeviceName string `json:"device_name"`
		DeviceID   string `json:"device_id"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Verify PIN
	if !s.pairing.VerifyPIN(req.PIN) {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   "Invalid PIN code",
		})
		return
	}

	// Generate JWT token
	token, err := auth.GenerateToken(req.DeviceID, req.DeviceName)
	if err != nil {
		http.Error(w, "Failed to generate token", http.StatusInternalServerError)
		return
	}

	ip := getLocalIP()
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":     true,
		"token":       token,
		"ws_endpoint": fmt.Sprintf("ws://%s:%d/ws", ip, s.port),
	})

	log.Printf("Device paired: %s (%s)", req.DeviceName, req.DeviceID)
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	log.Printf("WebSocket connection attempt from %s", r.RemoteAddr)

	deviceID := "unknown-device"

	// Check if local network bypass applies
	isLocalBypass := false
	if s.allowLocalNoAuth {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			host = r.RemoteAddr
		}
		host = strings.Trim(host, "[]")
		ip := net.ParseIP(host)
		if host == "127.0.0.1" || host == "::1" || host == "localhost" || (ip != nil && ip.IsPrivate()) {
			isLocalBypass = true
			deviceID = "local-dev"
		}
	}

	token := r.URL.Query().Get("token")
	if token == "" && !isLocalBypass {
		log.Printf("WebSocket error: no token provided")
		http.Error(w, "Unauthorized: no token", http.StatusUnauthorized)
		return
	}

	if token != "" {
		if claims, err := auth.ValidateToken(token); err == nil {
			deviceID = claims.DeviceID
			log.Printf("WebSocket token valid for device: %s", deviceID)
		} else if !isLocalBypass {
			log.Printf("WebSocket error: invalid token - %v", err)
			http.Error(w, "Unauthorized: invalid token", http.StatusUnauthorized)
			return
		}
	}

	// Upgrade to WebSocket with MCP configuration
	websocket.ServeWs(s.hub, w, r, deviceID, s.workDir, s.mcpConfig, s.openclawBridge)
}

// OpenClaw API Handlers

func (s *Server) handleOpenClawStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	connected := false
	if s.openclawClient != nil {
		connected = s.openclawClient.IsConnected()
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"enabled":   s.openclawConfig != nil && s.openclawConfig.Enabled,
		"connected": connected,
	})
}

// withTaskAuth runs next if JWT valid, or if allowLocalNoAuth and request from localhost/LAN
func (s *Server) withTaskAuth(w http.ResponseWriter, r *http.Request, next http.HandlerFunc) {
	if s.allowLocalNoAuth {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			host = r.RemoteAddr
		}
		// Strip IPv6 brackets if present
		host = strings.Trim(host, "[]")
		ip := net.ParseIP(host)
		if host == "127.0.0.1" || host == "::1" || host == "localhost" || (ip != nil && ip.IsPrivate()) {
			next(w, r)
			return
		}
	}

	token := r.URL.Query().Get("token")
	if token == "" {
		if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
			token = strings.TrimPrefix(h, "Bearer ")
		}
	}
	if token != "" {
		if _, err := auth.ValidateToken(token); err == nil {
			next(w, r)
			return
		}
	}
	w.WriteHeader(http.StatusUnauthorized)
	json.NewEncoder(w).Encode(map[string]interface{}{"error": "missing or invalid token"})
}

// Task API handlers (with JWT auth; localhost can skip auth when --allow-local-no-auth)
func (s *Server) handleTasksAPI(w http.ResponseWriter, r *http.Request) {
	s.withTaskAuth(w, r, func(w2 http.ResponseWriter, r2 *http.Request) {
		switch r2.Method {
		case http.MethodGet:
			s.taskHandlers.ListTasks(w2, r2)
		case http.MethodPost:
			s.taskHandlers.CreateTask(w2, r2)
		default:
			http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})
}

func (s *Server) handleTaskByIDAPI(w http.ResponseWriter, r *http.Request) {
	s.withTaskAuth(w, r, func(w2 http.ResponseWriter, r2 *http.Request) {
		pathSuffix := strings.TrimPrefix(r2.URL.Path, "/api/tasks/")

		if pathSuffix == "" {
			http.Redirect(w2, r2, "/api/tasks", http.StatusMovedPermanently)
			return
		}

		if strings.HasSuffix(pathSuffix, "/plan") {
			if r2.Method == http.MethodGet {
				s.handleTaskPlanAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/generate-plan") {
			if r2.Method == http.MethodPost {
				s.handleTaskGeneratePlanAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/phase-advance") {
			if r2.Method == http.MethodPost {
				s.handleTaskPhaseAdvanceAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/phase-release") {
			if r2.Method == http.MethodPost {
				s.handleTaskPhaseReleaseAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/phase-pipeline") {
			if r2.Method == http.MethodPost {
				s.handleTaskPhasePipelineAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/auto-execute") {
			if r2.Method == http.MethodPost {
				s.handleTaskAutoExecuteAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/run-phase") {
			if r2.Method == http.MethodPost {
				s.handleTaskRunPhaseAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/open-cursor") {
			if r2.Method == http.MethodPost {
				s.handleTaskOpenCursorAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/execute") {
			if r2.Method == http.MethodPost {
				s.handleTaskExecuteAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/tmux-focus") {
			if r2.Method == http.MethodPost {
				s.handleTaskTmuxFocusAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/agent-start") {
			if r2.Method == http.MethodPost {
				s.handleTaskAgentStartAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		if strings.HasSuffix(pathSuffix, "/mark-phase-complete") {
			if r2.Method == http.MethodPost {
				s.handleTaskMarkPhaseCompleteAPI(w2, r2)
			} else {
				http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			}
			return
		}

		switch r2.Method {
		case http.MethodGet:
			s.taskHandlers.GetTask(w2, r2)
		case http.MethodPut:
			s.taskHandlers.UpdateTask(w2, r2)
		case http.MethodDelete:
			s.taskHandlers.DeleteTask(w2, r2)
		default:
			http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})
}

// handleTaskTmuxFocusAPI handles POST /api/tasks/:id/tmux-focus
// Runs tmux-focus-skill.js to open iTerm2 and attach to the agent's tmux session.
// The skill uses projectKey as the tmux session name (same as agent-start-skill.js).
func (s *Server) handleTaskTmuxFocusAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/tmux-focus")

	task, err := s.taskStore.GetByID(id)
	if err != nil || task == nil {
		http.Error(w, "task not found", http.StatusNotFound)
		return
	}

	// agent-start-skill.js uses projectKey as the tmux session name.
	// Pass --session directly so tmux-focus-skill doesn't need to query its own tasks-store.
	sessionName := task.ProjectKey
	if sessionName == "" {
		http.Error(w, "task has no projectKey — cannot determine tmux session name", http.StatusBadRequest)
		return
	}

	skillsBasePath := s.skillsPath
	if skillsBasePath == "" {
		skillsBasePath = filepath.Join(s.workDir, "skills")
	}

	// Try resolving the script path. First look in software-dev under skillsBasePath
	scriptPath := filepath.Join(skillsBasePath, "software-dev", "tmux-focus-skill.js")
	if _, statErr := os.Stat(scriptPath); statErr != nil {
		// Fallback in case skillsBasePath points directly to the subfolder
		scriptPath = filepath.Join(skillsBasePath, "tmux-focus-skill.js")
		if _, fallbackErr := os.Stat(scriptPath); fallbackErr != nil {
			http.Error(w, fmt.Sprintf("tmux-focus-skill.js not found in %s", skillsBasePath), http.StatusInternalServerError)
			return
		}
	}

	args := []string{filepath.Base(scriptPath), "focus", fmt.Sprintf("--session=%s", sessionName)}

	// Include paneId from task tmux metadata if available (set by agent-start-skill)
	if task.TmuxPaneId != "" {
		args = append(args, fmt.Sprintf("--paneId=%s", task.TmuxPaneId))
	}

	cmd := exec.Command("node", args...)
	cmd.Dir = filepath.Dir(scriptPath)
	output, err := cmd.Output()
	if err != nil {
		log.Printf("tmux-focus-skill failed for task %s (session=%s): %v", id, sessionName, err)
		http.Error(w, fmt.Sprintf("tmux-focus-skill failed: %v", err), http.StatusInternalServerError)
		return
	}

	log.Printf("tmux-focus-skill ok for task %s (session=%s)", id, sessionName)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"taskId":  id,
		"session": sessionName,
		"output":  string(output),
	})
}

// handleTaskAgentStartAPI handles POST /api/tasks/:id/agent-start?backend=ccr|cursor|claude
// Runs agent-start-skill.js which creates a tmux session, starts the agent, and records
// tmux metadata (session/window/paneId) on the task.
func (s *Server) handleTaskAgentStartAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/agent-start")

	task, err := s.taskStore.GetByID(id)
	if err != nil || task == nil {
		http.Error(w, "task not found", http.StatusNotFound)
		return
	}

	backend := r.URL.Query().Get("backend")
	if backend == "" {
		backend = "ccr"
	}
	phase := r.URL.Query().Get("phase")

	projectKey := task.ProjectKey
	if projectKey == "" {
		http.Error(w, "task has no projectKey", http.StatusBadRequest)
		return
	}

	skillsBasePath := s.skillsPath
	if skillsBasePath == "" {
		skillsBasePath = filepath.Join(s.workDir, "skills")
	}

	// Try resolving the script path. First look in software-dev under skillsBasePath
	scriptPath := filepath.Join(skillsBasePath, "software-dev", "agent-start-skill.js")
	if _, statErr := os.Stat(scriptPath); statErr != nil {
		// Fallback in case skillsBasePath points directly to the subfolder
		scriptPath = filepath.Join(skillsBasePath, "agent-start-skill.js")
		if _, fallbackErr := os.Stat(scriptPath); fallbackErr != nil {
			http.Error(w, fmt.Sprintf("agent-start-skill.js not found in %s", skillsBasePath), http.StatusInternalServerError)
			return
		}
	}

	// Run synchronously so we can capture the HANDOFF output
	args := []string{filepath.Base(scriptPath), "start", projectKey, id, backend}
	if task.PlanPath != "" {
		args = append(args, fmt.Sprintf("--plan=%s", task.PlanPath))
	}
	if phase != "" {
		args = append(args, fmt.Sprintf("--phase=%s", phase))
	}

	cmd := exec.Command("node", args...)
	cmd.Dir = filepath.Dir(scriptPath)
	cmd.Env = append(cmd.Environ(),
		fmt.Sprintf("TASK_API_URL=http://%s:%d", s.taskAPIURLHost(), s.port),
		"TASK_API_TOKEN=internal-execute-token",
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("agent-start-skill failed for task %s backend %s: %v\nOutput: %s", id, backend, err, string(output))
		http.Error(w, fmt.Sprintf("agent-start-skill failed: %v\n%s", err, string(output)), http.StatusInternalServerError)
		return
	}

	log.Printf("agent-start-skill ok for task %s backend=%s", id, backend)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"taskId":  id,
		"backend": backend,
		"output":  string(output),
	})
}

// handleTaskMarkPhaseCompleteAPI handles POST /api/tasks/:id/mark-phase-complete?phase=code|test|done
// Called by run-with-status.sh after successful CCR/cursor execution to mark the plan phase checklist complete.
func (s *Server) handleTaskMarkPhaseCompleteAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/mark-phase-complete")

	task, err := s.taskStore.GetByID(id)
	if err != nil || task == nil {
		http.Error(w, "task not found", http.StatusNotFound)
		return
	}

	phase := r.URL.Query().Get("phase")
	if phase == "" {
		http.Error(w, "phase query param required", http.StatusBadRequest)
		return
	}

	if task.PlanPath == "" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "skipped": true, "reason": "no planPath"})
		return
	}

	if err := tasks.MarkPhaseSectionComplete(task.PlanPath, phase); err != nil {
		log.Printf("mark-phase-complete failed for task %s phase %s: %v", id, phase, err)
		http.Error(w, fmt.Sprintf("mark phase complete failed: %v", err), http.StatusInternalServerError)
		return
	}

	log.Printf("mark-phase-complete ok for task %s phase=%s", id, phase)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "taskId": id, "phase": phase})
}

func (s *Server) handleTaskPlanAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/plan")

	task, err := s.taskStore.GetByID(id)
	if err != nil || task == nil {
		http.Error(w, "task not found", http.StatusNotFound)
		return
	}

	if task.PlanPath == "" {
		http.Error(w, "task has no plan file", http.StatusNotFound)
		return
	}

	planPath := task.PlanPath
	if !filepath.IsAbs(planPath) {
		// 相对路径：只以用户配置的项目目录（projects.json 中该项目的 path）为前缀，不用 proxy workDir 作为项目目录
		if task.ProjectKey == "" {
			http.Error(w, "task has no projectKey, cannot resolve relative plan path", http.StatusBadRequest)
			return
		}
		proj, err := s.projectRegistry.Get(task.ProjectKey)
		if err != nil || proj == nil || proj.Path == "" {
			http.Error(w, "project not found or has no path, cannot resolve relative plan path", http.StatusBadRequest)
			return
		}
		baseDir := proj.Path
		if !filepath.IsAbs(baseDir) {
			// 项目 path 为相对路径时，仅相对于 proxy workDir 解析一次，得到项目目录
			baseDir = filepath.Join(s.workDir, baseDir)
		}
		baseDir, _ = filepath.Abs(baseDir)
		planPath = filepath.Join(baseDir, planPath)
		var absErr error
		planPath, absErr = filepath.Abs(planPath)
		if absErr != nil {
			http.Error(w, "invalid plan path", http.StatusBadRequest)
			return
		}
	}

	if _, err := os.Stat(planPath); err != nil {
		if os.IsNotExist(err) {
			w.Header().Set("X-Plan-Error", "file-not-found")
			http.Error(w, "plan file not found at path (check proxy workdir and task planPath)", http.StatusNotFound)
			return
		}
		http.Error(w, "plan file unreadable", http.StatusInternalServerError)
		return
	}

	http.ServeFile(w, r, planPath)
}

func (s *Server) runOpenClawIntegrationCmd(w http.ResponseWriter, command string, args []string) {
	skillsBasePath := s.skillsPath
	if skillsBasePath == "" {
		skillsBasePath = filepath.Join(s.workDir, "skills")
	}

	scriptPath := filepath.Join(skillsBasePath, "software-dev", "openclaw-integration.js")
	if _, statErr := os.Stat(scriptPath); statErr != nil {
		scriptPath = filepath.Join(skillsBasePath, "openclaw-integration.js")
		if _, fallbackErr := os.Stat(scriptPath); fallbackErr != nil {
			http.Error(w, fmt.Sprintf("openclaw-integration.js not found in %s", skillsBasePath), http.StatusInternalServerError)
			return
		}
	}

	cmdArgs := append([]string{filepath.Base(scriptPath), command}, args...)
	cmd := exec.Command("node", cmdArgs...)
	cmd.Dir = filepath.Dir(scriptPath)
	cmd.Env = append(cmd.Environ(),
		fmt.Sprintf("TASK_API_URL=http://%s:%d", s.taskAPIURLHost(), s.port),
		"TASK_API_TOKEN=internal-execute-token",
		"PATH="+os.Getenv("PATH"),
	)

	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("openclaw-integration %s failed: %v\nOutput: %s", command, err, string(output))
		http.Error(w, fmt.Sprintf("%s failed: %v\n%s", command, err, string(output)), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"output":  string(output),
	})
}

// runOpenClawIntegrationCmdAsync 在后台执行命令，不阻塞 HTTP；用于 auto-execute/phase-pipeline 等长时间任务，保证客户端断开也不中断。
func (s *Server) runOpenClawIntegrationCmdAsync(taskID, command string, args []string) bool {
	s.runningPipelinesMu.Lock()
	if s.runningPipelines[taskID] {
		s.runningPipelinesMu.Unlock()
		return false
	}
	s.runningPipelines[taskID] = true
	s.runningPipelinesMu.Unlock()

	skillsBasePath := s.skillsPath
	if skillsBasePath == "" {
		skillsBasePath = filepath.Join(s.workDir, "skills")
	}
	scriptPath := filepath.Join(skillsBasePath, "software-dev", "openclaw-integration.js")
	if _, statErr := os.Stat(scriptPath); statErr != nil {
		scriptPath = filepath.Join(skillsBasePath, "openclaw-integration.js")
		if _, fallbackErr := os.Stat(scriptPath); fallbackErr != nil {
			s.runningPipelinesMu.Lock()
			delete(s.runningPipelines, taskID)
			s.runningPipelinesMu.Unlock()
			return true
		}
	}

	cmdArgs := append([]string{filepath.Base(scriptPath), command}, args...)
	cmd := exec.Command("node", cmdArgs...)
	cmd.Dir = filepath.Dir(scriptPath)
	cmd.Env = append(cmd.Environ(),
		fmt.Sprintf("TASK_API_URL=http://%s:%d", s.taskAPIURLHost(), s.port),
		"TASK_API_TOKEN=internal-execute-token",
		"PATH="+os.Getenv("PATH"),
	)

	log.Printf("[async] starting openclaw-integration %s %s (args: %v)", command, taskID, args)
	go func() {
		output, err := cmd.CombinedOutput()
		outStr := strings.TrimSpace(string(output))
		asyncDetached := command == "run-phase" && err == nil &&
			(strings.Contains(outStr, `"async": true`) || strings.Contains(outStr, `"async":true`))

		if asyncDetached {
			log.Printf("[async] openclaw-integration %s %s entered async tmux mode; keeping running lock until phase-release", command, taskID)
		} else {
			s.runningPipelinesMu.Lock()
			delete(s.runningPipelines, taskID)
			s.runningPipelinesMu.Unlock()
		}

		if err != nil {
			log.Printf("[async] openclaw-integration %s %s failed: %v\nOutput: %s", command, taskID, err, outStr)
		} else {
			if len(outStr) > 0 {
				const maxLog = 600
				if len(outStr) > maxLog {
					outStr = outStr[:maxLog] + "..."
				}
				log.Printf("[async] openclaw-integration %s %s completed\nOutput: %s", command, taskID, outStr)
			} else {
				log.Printf("[async] openclaw-integration %s %s completed", command, taskID)
			}
		}
	}()
	return true
}

func (s *Server) handleTaskGeneratePlanAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/generate-plan")
	task, err := s.taskStore.GetByID(id)
	if err != nil || task == nil {
		http.Error(w, "task not found", http.StatusNotFound)
		return
	}
	// 与 code/test/done 一致：在 tmux 中执行，可 tmux attach 查看
	if task.ProjectKey == "" {
		http.Error(w, "task has no projectKey, cannot start plan generation in tmux", http.StatusBadRequest)
		return
	}
	stPlanning := tasks.StatusPlanning
	if _, err := s.taskStore.Update(id, &tasks.UpdateTaskRequest{Status: &stPlanning}); err != nil {
		// non-fatal, continue to start
	}
	started := s.runAgentStartSkillAsync(task, "plan")
	if !started {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   "该任务已有阶段在执行中",
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"accepted": true,
		"taskId":   id,
		"message":  "已在 tmux 中启动生成计划，可执行 tmux attach -t " + task.ProjectKey + " 查看",
	})
}

func (s *Server) handleTaskPhaseAdvanceAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/phase-advance")

	phase := r.URL.Query().Get("phase")
	args := []string{id}
	if phase != "" {
		args = append(args, phase)
	}
	s.runOpenClawIntegrationCmd(w, "phase-advance", args)
}

func (s *Server) handleTaskPhaseReleaseAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/phase-release")

	resolvedID := id
	var phaseForChecklist string
	if s.taskStore != nil {
		if task, err := s.taskStore.GetByID(id); err == nil && task != nil && task.ID != "" {
			resolvedID = task.ID
			// If client passes ?phase=code|test|done, use it to ensure checklist is marked complete.
			phaseForChecklist = r.URL.Query().Get("phase")
			if phaseForChecklist != "" && task.PlanPath != "" {
				if err := tasks.MarkPhaseSectionComplete(task.PlanPath, phaseForChecklist); err != nil {
					log.Printf("phase-release: mark phase %s complete failed for task %s: %v", phaseForChecklist, task.ID, err)
				} else {
					log.Printf("phase-release: ensured checklist complete for task %s phase=%s", task.ID, phaseForChecklist)
				}
			}
		}
	}

	s.runningPipelinesMu.Lock()
	delete(s.runningPipelines, id)
	delete(s.runningPipelines, resolvedID)
	s.runningPipelinesMu.Unlock()

	log.Printf("phase-release ok for task %s (resolved=%s)", id, resolvedID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"taskId":   id,
		"resolved": resolvedID,
		"released": true,
	})
}

func (s *Server) handleTaskPhasePipelineAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/phase-pipeline")
	s.runOpenClawIntegrationCmd(w, "phase-pipeline", []string{id})
}

// handleTaskAutoExecuteAPI 后台执行 auto-execute，立即返回 202，保证任务不因客户端断开或超时而中断。根据任务的后端类型执行。
func (s *Server) handleTaskAutoExecuteAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/auto-execute")
	if id == "" {
		http.Error(w, "task id required", http.StatusBadRequest)
		return
	}
	autoArgs := []string{id}
	if s.taskStore != nil {
		if task, _ := s.taskStore.GetByID(id); task != nil && task.Backend != "" {
			autoArgs = append(autoArgs, "--backend="+task.Backend)
		}
	}
	started := s.runOpenClawIntegrationCmdAsync(id, "auto-execute", autoArgs)
	if !started {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   "该任务已有流水线在执行中，请稍后查看状态",
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"accepted": true,
		"taskId":   id,
		"message":  "已提交后台执行，请通过任务状态或刷新查看进度，执行不会因关闭页面而中断",
	})
}

// handleTaskRunPhaseAPI 执行单个阶段（供定时触发用），后台运行，返回 202。根据任务的后端类型执行。
func (s *Server) handleTaskRunPhaseAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/run-phase")
	phase := r.URL.Query().Get("phase")
	if id == "" || phase == "" {
		http.Error(w, "task id and phase required (e.g. ?phase=code)", http.StatusBadRequest)
		return
	}
	if phase != "plan" && phase != "code" && phase != "test" && phase != "done" {
		http.Error(w, "phase must be plan, code, test, or done", http.StatusBadRequest)
		return
	}
	runPhaseArgs := []string{id, phase}
	var phaseStatus string
	switch phase {
	case "code":
		phaseStatus = tasks.StatusCoding
	case "test":
		phaseStatus = tasks.StatusTesting
	case "done":
		phaseStatus = tasks.StatusSubmitting
	}
	if phaseStatus != "" && s.taskStore != nil {
		if _, err := s.taskStore.Update(id, &tasks.UpdateTaskRequest{Status: &phaseStatus}); err != nil {
			// non-fatal
		}
	}
	if s.taskStore != nil {
		if task, _ := s.taskStore.GetByID(id); task != nil && task.Backend != "" {
			runPhaseArgs = append(runPhaseArgs, "--backend="+task.Backend)
		}
	}
	started := s.runOpenClawIntegrationCmdAsync(id, "run-phase", runPhaseArgs)
	if !started {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   "该任务已有阶段在执行中",
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"accepted": true,
		"taskId":   id,
		"phase":    phase,
		"message":  "阶段已提交后台执行",
	})
}

// prevPhaseFor returns the phase that must be completed before running the given phase.
func prevPhaseFor(phase string) string {
	switch phase {
	case "code":
		return "plan"
	case "test":
		return "code"
	case "done":
		return "test"
	default:
		return ""
	}
}

// nextPhaseFor returns the phase after the given one (code->test, test->done); empty if done or unknown.
func nextPhaseFor(phase string) string {
	switch phase {
	case "plan":
		return "code"
	case "code":
		return "test"
	case "test":
		return "done"
	default:
		return ""
	}
}

// runPhaseWatcher 定时分析任务，与界面手动按钮逻辑一致：无 plan 触发 generate-plan，有 plan 按 task.phase 触发 agent-start（code/test/done）；终态为 plan 的 Execution Log 中 todo 全部勾选完成。
func (s *Server) runPhaseWatcher() {
	ticker := time.NewTicker(s.phaseWatcherInterval)
	defer ticker.Stop()
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			s.triggerNextPhases()
		}
	}
}

func (s *Server) triggerNextPhases() {
	if s.taskStore == nil || s.skillsPath == "" {
		return
	}
	all, err := s.taskStore.GetAll()
	if err != nil || len(all) == 0 {
		return
	}

	for _, task := range all {
		// Only check tasks that are in statuses we can automate (exclude planning/coding to avoid duplicate trigger)
		canAutomate := task.Status == tasks.StatusPlanned || task.Status == tasks.StatusInProgress ||
			task.Status == tasks.StatusPending || task.Status == tasks.StatusConfirmed ||
			task.Status == tasks.StatusTesting || task.Status == tasks.StatusSubmitting
		if !canAutomate {
			continue
		}

		// 终态：plan 中 Execution Log 的 todo 全部勾选完成则不再触发
		if task.PlanPath != "" {
			completed, total := tasks.ParsePlanProgress(task.PlanPath)
			if total > 0 && completed == total {
				continue // plan todo list 已全部完成，跳过
			}
		}

		// Determine target phase（与界面手动按钮一致：无 plan 则生成计划，有 plan 则按当前 phase 执行对应阶段）
		targetPhase := task.Phase
		if targetPhase == "" {
			if task.PlanPath == "" {
				targetPhase = "plan"
			} else {
				targetPhase = "code"
			}
		}
		// 已有 PlanPath 且 phase=plan 表示计划已生成完成，应执行 code 而非 run-phase plan（plan 阶段仅校验，不生成代码）
		if targetPhase == "plan" && task.PlanPath != "" {
			targetPhase = "code"
			if _, err := s.taskStore.Update(task.ID, &tasks.UpdateTaskRequest{Phase: &targetPhase}); err == nil {
				task.Phase = targetPhase
				log.Printf("[Automation] Task %s phase plan with PlanPath → 推进为 code，触发代码执行", task.ID)
			}
			// 标记 plan 阶段已完成，否则 prevPhase 检查会阻断 code 触发（IsPhaseCompleted("plan") 返回 false → continue 跳过）
			if err := tasks.MarkPhaseSectionComplete(task.PlanPath, "plan"); err != nil {
				log.Printf("[Automation] Task %s mark plan section complete: %v", task.ID, err)
			}
		}

		// Check if already running
		s.runningPipelinesMu.Lock()
		running := s.runningPipelines[task.ID]
		s.runningPipelinesMu.Unlock()
		if running {
			continue
		}

		// 无 plan 时在 tmux 中触发「生成计划」（含 OpenClaw 下发的 inProgress 且无 plan 的任务）
		if (task.Status == tasks.StatusConfirmed || task.Status == tasks.StatusPending || task.Status == tasks.StatusInProgress) && task.PlanPath == "" {
			if task.ProjectKey == "" {
				// 无 projectKey 时无法 agent-start，退化为异步跑 openclaw generate-plan
				log.Printf("[Automation] Task %s has no plan and no projectKey, triggering generate-plan (async)...", task.ID)
				s.runOpenClawIntegrationCmdAsync(task.ID, "generate-plan", []string{task.ID, "--agent"})
			} else {
				log.Printf("[Automation] Task %s (%s) has no plan. Triggering generate-plan in tmux (agent-start phase=plan)...", task.ID, task.Status)
				stPlanning := tasks.StatusPlanning
				if _, err := s.taskStore.Update(task.ID, &tasks.UpdateTaskRequest{Status: &stPlanning}); err == nil {
					task.Status = tasks.StatusPlanning
				}
				s.runAgentStartSkillAsync(task, "plan")
			}
			continue
		}

		if task.PlanPath != "" && (task.Status == tasks.StatusPlanned || task.Status == tasks.StatusInProgress || task.Status == tasks.StatusConfirmed || task.Status == tasks.StatusTesting || task.Status == tasks.StatusSubmitting) {
			// 注意：phase 推进（code→test→done）的权利完全归 runPhaseOnly→advancePhase，
			// phaseWatcher 不基于 plan checkbox 自动推进，避免 AI 预先勾选导致阶段跳过执行。
			// 这里仅对 task.phase="" 的历史任务做补全（如果 plan 文件 meta 中有 phase 则同步）。
			// 从 plan meta 补全 phase（历史任务 phase="" 时）和 projectKey（老任务无 projectKey 时）
			if task.Phase == "" || task.ProjectKey == "" {
				meta := tasks.ParsePlanMeta(task.PlanPath)
				if task.Phase == "" {
					if metaPhase := strings.TrimSpace(meta["phase"]); metaPhase != "" && metaPhase != "plan" {
						targetPhase = metaPhase
						log.Printf("[Automation] Task %s phase filled from plan meta: %s", task.ID, targetPhase)
					}
				}
				if task.ProjectKey == "" {
					if k := strings.TrimSpace(meta["projectKey"]); k != "" {
						if _, err := s.taskStore.Update(task.ID, &tasks.UpdateTaskRequest{ProjectKey: &k}); err == nil {
							task.ProjectKey = k
							log.Printf("[Automation] Task %s projectKey filled from plan meta: %s", task.ID, k)
						}
					}
				}
			}
			// 确保 task.phase 与 targetPhase 一致，避免 runPhaseOnly 因 task.phase="" 被当成 "plan" 而跳过执行
			if task.Phase != targetPhase {
				if _, err := s.taskStore.Update(task.ID, &tasks.UpdateTaskRequest{Phase: &targetPhase}); err == nil {
					task.Phase = targetPhase
				}
			}
			runPhaseArgs := []string{task.ID, targetPhase}
			if task.Backend != "" {
				runPhaseArgs = append(runPhaseArgs, "--backend="+task.Backend)
			}
			// 触发前写入进行中状态，避免重复触发。done 阶段仅在成功启动 run-phase 后再设为「提交中」，避免先被设为提交中导致下一轮误判不触发
			var phaseStatus string
			switch targetPhase {
			case "code":
				phaseStatus = tasks.StatusCoding
			case "test":
				phaseStatus = tasks.StatusTesting
			case "done":
				phaseStatus = tasks.StatusSubmitting
			}
			if phaseStatus != "" && targetPhase != "done" {
				if _, err := s.taskStore.Update(task.ID, &tasks.UpdateTaskRequest{Status: &phaseStatus}); err == nil {
					task.Status = phaseStatus
				}
			}
			log.Printf("[Automation] Task %s (%s) phase %s backend %s. Triggering run-phase...", task.ID, task.Status, targetPhase, task.Backend)
			started := s.runOpenClawIntegrationCmdAsync(task.ID, "run-phase", runPhaseArgs)
			if started && targetPhase == "done" && phaseStatus != "" {
				if _, err := s.taskStore.Update(task.ID, &tasks.UpdateTaskRequest{Status: &phaseStatus}); err == nil {
					task.Status = phaseStatus
				}
			}
			continue
		}
	}
}

// runAgentStartSkillAsync mimics handleTaskAgentStartAPI but runs in the background.
func (s *Server) runAgentStartSkillAsync(task *tasks.Task, phase string) bool {
	taskID := task.ID
	s.runningPipelinesMu.Lock()
	if s.runningPipelines[taskID] {
		s.runningPipelinesMu.Unlock()
		return false
	}
	s.runningPipelines[taskID] = true
	s.runningPipelinesMu.Unlock()

	backend := task.Backend
	if backend == "" {
		backend = "ccr"
	}

	projectKey := task.ProjectKey
	if projectKey == "" && task.PlanPath != "" {
		// 老任务可能无 projectKey，从 plan 的 meta 中读取并回写
		meta := tasks.ParsePlanMeta(task.PlanPath)
		if k := strings.TrimSpace(meta["projectKey"]); k != "" {
			projectKey = k
			if _, err := s.taskStore.Update(task.ID, &tasks.UpdateTaskRequest{ProjectKey: &projectKey}); err == nil {
				log.Printf("[Automation] Task %s projectKey filled from plan meta: %s", taskID, projectKey)
			}
		}
	}
	if projectKey == "" {
		log.Printf("[Automation] Task %s has no projectKey, skipping agent-start", taskID)
		s.runningPipelinesMu.Lock()
		delete(s.runningPipelines, taskID)
		s.runningPipelinesMu.Unlock()
		return false
	}

	skillsBasePath := s.skillsPath
	if skillsBasePath == "" {
		skillsBasePath = filepath.Join(s.workDir, "skills")
	}

	scriptPath := filepath.Join(skillsBasePath, "software-dev", "agent-start-skill.js")
	if _, statErr := os.Stat(scriptPath); statErr != nil {
		scriptPath = filepath.Join(skillsBasePath, "agent-start-skill.js")
		if _, fallbackErr := os.Stat(scriptPath); fallbackErr != nil {
			log.Printf("[Automation] agent-start-skill.js not found in %s", skillsBasePath)
			s.runningPipelinesMu.Lock()
			delete(s.runningPipelines, taskID)
			s.runningPipelinesMu.Unlock()
			return false
		}
	}

	args := []string{filepath.Base(scriptPath), "start", projectKey, taskID, backend}
	if task.PlanPath != "" {
		args = append(args, fmt.Sprintf("--plan=%s", task.PlanPath))
	}
	if phase != "" {
		args = append(args, fmt.Sprintf("--phase=%s", phase))
	}

	cmd := exec.Command("node", args...)
	cmd.Dir = filepath.Dir(scriptPath)
	cmd.Env = append(cmd.Environ(),
		fmt.Sprintf("TASK_API_URL=http://%s:%d", s.taskAPIURLHost(), s.port),
		"TASK_API_TOKEN=internal-execute-token",
		"PATH="+os.Getenv("PATH"),
	)

	go func() {
		defer func() {
			s.runningPipelinesMu.Lock()
			delete(s.runningPipelines, taskID)
			s.runningPipelinesMu.Unlock()
		}()
		output, err := cmd.CombinedOutput()
		if err != nil {
			log.Printf("[Automation] agent-start-skill %s failed: %v\nOutput: %s", taskID, err, string(output))
		} else {
			log.Printf("[Automation] agent-start-skill %s completed successfully", taskID)
		}
	}()

	return true
}

func (s *Server) handleTaskOpenCursorAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/open-cursor")

	task, err := s.taskStore.GetByID(id)
	if err != nil || task == nil {
		http.Error(w, "task not found", http.StatusNotFound)
		return
	}

	if task.ProjectKey == "" || task.PlanPath == "" {
		http.Error(w, "task has no project or plan", http.StatusBadRequest)
		return
	}

	project, err := s.projectRegistry.Get(task.ProjectKey)
	if err != nil || project == nil {
		http.Error(w, "project not found", http.StatusNotFound)
		return
	}

	// 解析 plan 路径（与 handleTaskPlanAPI 一致：相对路径以项目目录为前缀）
	planPath := task.PlanPath
	if !filepath.IsAbs(planPath) {
		baseDir := project.Path
		if !filepath.IsAbs(baseDir) {
			baseDir = filepath.Join(s.workDir, baseDir)
		}
		baseDir, _ = filepath.Abs(baseDir)
		planPath = filepath.Join(baseDir, planPath)
		planPath, _ = filepath.Abs(planPath)
	}

	projectDir := project.Path
	if !filepath.IsAbs(projectDir) {
		projectDir = filepath.Join(s.workDir, projectDir)
	}
	projectDir, _ = filepath.Abs(projectDir)

	// 用 shell 脚本 stream-progress.sh 执行 plan（与 agent-start cursor 一致）
	skillsBasePath := s.skillsPath
	if skillsBasePath == "" {
		skillsBasePath = filepath.Join(s.workDir, "skills")
	}
	streamScript := filepath.Join(skillsBasePath, "software-dev", "stream-progress.sh")
	if _, statErr := os.Stat(streamScript); statErr != nil {
		http.Error(w, fmt.Sprintf("stream-progress.sh not found at %s", streamScript), http.StatusInternalServerError)
		return
	}

	cmd := exec.Command("bash", streamScript, planPath, projectDir)
	cmd.Dir = projectDir
	cmd.Env = append(cmd.Environ(),
		fmt.Sprintf("TASK_API_URL=http://%s:%d", s.taskAPIURLHost(), s.port),
		"TASK_API_TOKEN=internal-execute-token",
	)
	if err := cmd.Start(); err != nil {
		log.Printf("Failed to start stream-progress.sh: %v", err)
		http.Error(w, fmt.Sprintf("failed to start cursor plan execution: %v", err), http.StatusInternalServerError)
		return
	}
	log.Printf("Started cursor plan execution (stream-progress.sh) for task %s, plan %s, pid: %d", id, planPath, cmd.Process.Pid)

	json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

func (s *Server) handleTaskExecuteAPI(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	id = strings.TrimSuffix(id, "/execute")

	task, err := s.taskStore.GetByID(id)
	if err != nil || task == nil {
		http.Error(w, "task not found", http.StatusNotFound)
		return
	}

	executor := r.URL.Query().Get("executor")
	if executor == "" {
		executor = "claude" // Default to claude
	}

	if task.ProjectKey == "" {
		http.Error(w, "task has no project", http.StatusBadRequest)
		return
	}

	// cursor: delegate to agent-start-skill.js which spawns the Cursor agent CLI
	// in a dedicated tmux window (same as POST /api/tasks/:id/agent-start?backend=cursor)
	if executor == "cursor" {
		// Rewrite the URL so handleTaskAgentStartAPI reads /api/tasks/<id>/agent-start
		r2 := r.Clone(r.Context())
		r2.URL.Path = "/api/tasks/" + id + "/agent-start"
		q := r2.URL.Query()
		q.Set("backend", "cursor")
		r2.URL.RawQuery = q.Encode()
		s.handleTaskAgentStartAPI(w, r2)
		return
	}

	project, err := s.projectRegistry.Get(task.ProjectKey)
	if err != nil || project == nil {
		http.Error(w, "project not found", http.StatusNotFound)
		return
	}

	// Determine skills path
	skillsBasePath := s.skillsPath
	if skillsBasePath == "" {
		skillsBasePath = filepath.Join(s.workDir, "skills")
	}

	scriptPath := filepath.Join(skillsBasePath, "software-dev", "capabilities", "execute-plan", "run.js")

	// Log path: 可指定目录；默认软件安装目录/logs，绝对路径便于日志详情可见；文件名关联 taskId
	logPath := r.URL.Query().Get("logPath")
	if logPath == "" {
		logsDir := resolveExecutionLogDir(skillsBasePath)
		// Use stable filename for task execution to allow appending output (exec-{taskId}.log)
		logPath = filepath.Join(logsDir, fmt.Sprintf("exec-%s.log", id))
	}
	if abs, err := filepath.Abs(logPath); err == nil {
		logPath = abs
	}

	// Spawn the node process with --log for execution trace
	cmd := exec.Command("node", scriptPath, "--run", id, "--log", logPath)

	// Prepare environment variables
	cmd.Env = append(cmd.Environ(),
		fmt.Sprintf("TASK_API_URL=http://%s:%d", s.taskAPIURLHost(), s.port),
		"TASK_API_TOKEN=internal-execute-token",
	)

	if err := cmd.Start(); err != nil {
		log.Printf("Failed to spawn executor: %v", err)
		http.Error(w, fmt.Sprintf("failed to spawn executor: %v", err), http.StatusInternalServerError)
		return
	}

	log.Printf("Spawned %s executor for task %s (pid: %d), log: %s", executor, id, cmd.Process.Pid, logPath)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"pid":      cmd.Process.Pid,
		"executor": executor,
		"logPath":  logPath,
	})
}

func (s *Server) handleOpenClawSendTask(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	if s.openclawBridge == nil {
		http.Error(w, "OpenClaw integration not enabled", http.StatusServiceUnavailable)
		return
	}

	var req struct {
		Prompt   string `json:"prompt"`
		Skill    string `json:"skill,omitempty"`
		Priority string `json:"priority,omitempty"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.Prompt == "" {
		http.Error(w, "prompt is required", http.StatusBadRequest)
		return
	}

	reqID, err := s.openclawBridge.SendTaskToAgent(req.Prompt, req.Skill, req.Priority)
	if err != nil {
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
		return
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":    true,
		"request_id": reqID,
	})
}

// Skill API handlers

func (s *Server) handleSkillPaths(w http.ResponseWriter, r *http.Request) {
	s.withTaskAuth(w, r, func(w2 http.ResponseWriter, r2 *http.Request) {
		switch r2.Method {
		case http.MethodGet:
			paths, err := s.skillManager.GetPaths()
			if err != nil {
				http.Error(w2, err.Error(), http.StatusInternalServerError)
				return
			}
			json.NewEncoder(w2).Encode(map[string]interface{}{"paths": paths})

		case http.MethodPost:
			var req struct {
				Paths []string `json:"paths"`
			}
			if err := json.NewDecoder(r2.Body).Decode(&req); err != nil {
				http.Error(w2, "Invalid request body", http.StatusBadRequest)
				return
			}
			if err := s.skillManager.SetPaths(req.Paths); err != nil {
				http.Error(w2, err.Error(), http.StatusInternalServerError)
				return
			}
			json.NewEncoder(w2).Encode(map[string]interface{}{"success": true})

		default:
			http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})
}

func (s *Server) handleSkillsAPI(w http.ResponseWriter, r *http.Request) {
	s.withTaskAuth(w, r, func(w2 http.ResponseWriter, r2 *http.Request) {
		if r2.Method != http.MethodGet {
			http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Check if this is a content request: /api/skills/{id}/content
		path := strings.TrimPrefix(r2.URL.Path, "/api/skills")
		path = strings.TrimPrefix(path, "/")

		if path == "" {
			// List all skills
			skillList := s.skillManager.DiscoverSkills()
			if skillList == nil {
				skillList = []skills.Skill{}
			}
			json.NewEncoder(w2).Encode(skillList)
			return
		}

		if strings.HasSuffix(path, "/content") {
			// Get skill content: /api/skills/{id}/content
			id := strings.TrimSuffix(path, "/content")
			content, err := s.skillManager.ReadContent(id)
			if err != nil {
				http.Error(w2, err.Error(), http.StatusNotFound)
				return
			}
			w2.Header().Set("Content-Type", "text/markdown; charset=utf-8")
			io.WriteString(w2, content)
			return
		}

		http.Error(w2, "Not found", http.StatusNotFound)
	})
}

// Project API handlers

func (s *Server) handleProjectAPI(w http.ResponseWriter, r *http.Request) {
	s.withTaskAuth(w, r, func(w2 http.ResponseWriter, r2 *http.Request) {
		path := strings.TrimPrefix(r2.URL.Path, "/api/projects")
		path = strings.TrimPrefix(path, "/")

		switch r2.Method {
		case http.MethodGet:
			if path == "" {
				// List all projects
				proj, err := s.projectRegistry.GetAll()
				if err != nil {
					http.Error(w2, err.Error(), http.StatusInternalServerError)
					return
				}
				json.NewEncoder(w2).Encode(map[string]interface{}{"projects": proj})
			} else {
				// Get single project
				p, err := s.projectRegistry.Get(path)
				if err != nil {
					http.Error(w2, err.Error(), http.StatusInternalServerError)
					return
				}
				if p == nil {
					w2.WriteHeader(http.StatusNotFound)
					json.NewEncoder(w2).Encode(map[string]interface{}{"error": "project not found"})
					return
				}
				json.NewEncoder(w2).Encode(p)
			}

		case http.MethodPost:
			var p projects.Project
			if err := json.NewDecoder(r2.Body).Decode(&p); err != nil {
				http.Error(w2, "invalid JSON", http.StatusBadRequest)
				return
			}
			if p.Key == "" {
				w2.WriteHeader(http.StatusBadRequest)
				json.NewEncoder(w2).Encode(map[string]interface{}{"error": "key is required"})
				return
			}
			if err := s.projectRegistry.Upsert(p); err != nil {
				http.Error(w2, err.Error(), http.StatusInternalServerError)
				return
			}
			json.NewEncoder(w2).Encode(map[string]interface{}{"success": true, "project": p})

		case http.MethodDelete:
			if path == "" {
				http.Error(w2, "project key required", http.StatusBadRequest)
				return
			}
			ok, err := s.projectRegistry.Delete(path)
			if err != nil {
				http.Error(w2, err.Error(), http.StatusInternalServerError)
				return
			}
			if !ok {
				w2.WriteHeader(http.StatusNotFound)
				json.NewEncoder(w2).Encode(map[string]interface{}{"error": "project not found"})
				return
			}
			w2.WriteHeader(http.StatusNoContent)

		default:
			http.Error(w2, "Method not allowed", http.StatusMethodNotAllowed)
		}
	})
}

// Capability execution handler

func (s *Server) handleSkillExecute(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Skill execution is safe for any LAN caller – no JWT required.
	var req struct {
		Skill   string   `json:"skill"`
		Command string   `json:"command"`
		Args    []string `json:"args"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	if req.Skill == "" || req.Command == "" {
		http.Error(w, "skill and command are required", http.StatusBadRequest)
		return
	}

	log.Printf("[Server] ExecuteSkill skill=%s command=%s args=%v", req.Skill, req.Command, req.Args)

	handoff, err := s.skillManager.ExecuteSkill(req.Skill, req.Command, req.Args...)
	if err != nil {
		log.Printf("[Server] Skill execution error: %v (handoff: %s)", err, handoff)
		w.WriteHeader(http.StatusInternalServerError)
		if json.Valid([]byte(handoff)) {
			w.Write([]byte(handoff))
		} else {
			json.NewEncoder(w).Encode(map[string]interface{}{
				"ok":    false,
				"error": err.Error(),
				"raw":   handoff,
			})
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(handoff))
}

func (s *Server) handleCapabilityExecute(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	s.withTaskAuth(w, r, func(w2 http.ResponseWriter, r2 *http.Request) {
		var req struct {
			Capability  string `json:"capability"` // create-task, execute-plan, execute-plan-cursor
			Title       string `json:"title"`
			Description string `json:"description"`
			ProjectKey  string `json:"projectKey"`
			Priority    string `json:"priority,omitempty"`
		}

		if err := json.NewDecoder(r2.Body).Decode(&req); err != nil {
			http.Error(w2, "invalid JSON", http.StatusBadRequest)
			return
		}

		if req.Title == "" || req.ProjectKey == "" {
			w2.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w2).Encode(map[string]interface{}{"error": "title and projectKey are required"})
			return
		}

		if req.Description == "" {
			req.Description = req.Title
		}

		// Look up project
		project, err := s.projectRegistry.Get(req.ProjectKey)
		if err != nil || project == nil {
			w2.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w2).Encode(map[string]interface{}{"error": fmt.Sprintf("project %q not found", req.ProjectKey)})
			return
		}

		if s.taskStore == nil {
			http.Error(w2, "task store not available", http.StatusServiceUnavailable)
			return
		}

		// Create task with plan
		createReq := &tasks.CreateTaskRequest{
			Title:       req.Title,
			Description: req.Description,
			Priority:    req.Priority,
			ProjectKey:  req.ProjectKey,
		}

		task, err := s.taskStore.CreateWithPlan(createReq, project.Path, project.Name, project.TechStack)
		if err != nil {
			http.Error(w2, err.Error(), http.StatusInternalServerError)
			return
		}

		log.Printf("[Capability] Created task %s with plan at %s", task.TaskID, task.PlanPath)

		result := map[string]interface{}{
			"success": true,
			"task":    task,
		}

		// For execute-plan and execute-plan-cursor, also send to OpenClaw
		if req.Capability == "execute-plan" || req.Capability == "execute-plan-cursor" {
			if s.openclawBridge != nil {
				skillID := req.Capability
				prompt := fmt.Sprintf("请执行开发任务: %s\n\n描述: %s\n项目: %s (%s)\n计划文件: %s",
					req.Title, req.Description, project.Name, project.Path, task.PlanPath)

				reqID, err := s.openclawBridge.SendTaskToAgent(prompt, skillID, "p1")
				if err != nil {
					log.Printf("[Capability] Warning: failed to send to OpenClaw: %v", err)
					result["openclawError"] = err.Error()
				} else {
					result["openclawRequestId"] = reqID
					log.Printf("[Capability] Sent to OpenClaw: %s", reqID)
				}
			} else {
				result["openclawError"] = "OpenClaw not connected"
			}
		}

		w2.WriteHeader(http.StatusCreated)
		json.NewEncoder(w2).Encode(result)
	})
}

// resolveExecutionLogDir 返回执行日志目录（绝对路径）
// 优先读取 config.executionLogDir；默认软件安装目录/logs
func resolveExecutionLogDir(skillsBasePath string) string {
	configPath := filepath.Join(skillsBasePath, "software-dev", "config.json")
	data, err := os.ReadFile(configPath)
	if err == nil {
		var cfg struct {
			ExecutionLogDir string `json:"executionLogDir"`
			Settings        *struct {
				ExecutionLogDir string `json:"executionLogDir"`
			} `json:"settings"`
		}
		if json.Unmarshal(data, &cfg) == nil {
			dir := cfg.ExecutionLogDir
			if dir == "" && cfg.Settings != nil {
				dir = cfg.Settings.ExecutionLogDir
			}
			if dir != "" {
				if filepath.IsAbs(dir) {
					return dir
				}
				configDir := filepath.Dir(configPath)
				resolved := filepath.Clean(filepath.Join(configDir, dir))
				if abs, err := filepath.Abs(resolved); err == nil {
					return abs
				}
				return resolved
			}
		}
	}
	workspaceRoot := filepath.Dir(skillsBasePath)
	return filepath.Join(workspaceRoot, "logs")
}

// Helpers

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && isAllowedOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Content-Type", "application/json")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// isAllowedOrigin checks if the origin matches localhost or LAN patterns.
func isAllowedOrigin(origin string) bool {
	if strings.HasPrefix(origin, "http://localhost") ||
		strings.HasPrefix(origin, "https://localhost") ||
		strings.HasPrefix(origin, "http://127.0.0.1") ||
		strings.HasPrefix(origin, "https://127.0.0.1") ||
		strings.HasPrefix(origin, "http://192.168.") ||
		strings.HasPrefix(origin, "http://10.") {
		return true
	}
	return false
}

func getLocalIP() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return "127.0.0.1"
	}

	for _, addr := range addrs {
		if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				return ipnet.IP.String()
			}
		}
	}
	return "127.0.0.1"
}

func repeat(char rune, count int) []rune {
	result := make([]rune, count)
	for i := range result {
		result[i] = char
	}
	return result
}

// Chat History API handlers

func (s *Server) handleChatHistoryAPI(w http.ResponseWriter, r *http.Request) {
	if s.chatHistoryStore == nil {
		http.Error(w, "chat history store not available", http.StatusServiceUnavailable)
		return
	}

	switch r.Method {
	case http.MethodGet:
		// Get all chat history
		messages := s.chatHistoryStore.GetAll()
		json.NewEncoder(w).Encode(map[string]interface{}{
			"messages": messages,
			"count":    len(messages),
		})

	case http.MethodDelete:
		// Clear all chat history
		if err := s.chatHistoryStore.ClearAll(); err != nil {
			http.Error(w, fmt.Sprintf("failed to clear history: %v", err), http.StatusInternalServerError)
			return
		}
		log.Printf("[ChatHistory] All history cleared")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": true,
			"message": "All chat history cleared",
		})

	default:
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
	}
}
