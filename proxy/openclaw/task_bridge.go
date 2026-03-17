package openclaw

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"claude-voice-proxy/skills"
	"claude-voice-proxy/tasks"
	"claude-voice-proxy/websocket"
)

// activeRequest tracks the in-flight chat request for conversation thread isolation.
// Only one request at a time; responses are routed to the requesting device only.
type activeRequest struct {
	deviceID  string
	commandID string
	runID     string      // tracks the OpenClaw runId assigned to this request
	timer     *time.Timer // fallback: complete after idle
}

// isToolCallOrInternal returns true if the text looks like tool_call XML/JSON or other internal output
// that should not be shown as the assistant's reply (avoids "ID 错乱" / wrong content in bubble).
func isToolCallOrInternal(text string) bool {
	return strings.Contains(text, "<tool_call>") ||
		strings.Contains(text, "</tool_call>") ||
		strings.Contains(text, "</arg_value>") ||
		(strings.Contains(text, "tool_call") && strings.Contains(text, "delivery"))
}

// dedupeConsecutiveParagraphs removes duplicate paragraphs (split by \n\n), keeping first occurrence.
// If one paragraph is a prefix of another (e.g. "你的 AI" vs "你的 AI 助手。"), keeps only the longer one to avoid truncated repeats.
func dedupeConsecutiveParagraphs(s string) string {
	paragraphs := strings.Split(s, "\n\n")
	if len(paragraphs) <= 1 {
		return s
	}
	seen := make(map[string]bool)
	var out []string
	for _, p := range paragraphs {
		trimmed := strings.TrimSpace(p)
		if trimmed == "" {
			continue
		}
		if len(out) == 0 {
			if !seen[trimmed] {
				seen[trimmed] = true
				out = append(out, p)
			}
			continue
		}
		last := strings.TrimSpace(out[len(out)-1])
		if strings.HasPrefix(trimmed, last) && len(trimmed) > len(last) {
			// Current is longer and last is a prefix (e.g. truncated repeat) — keep the complete one
			delete(seen, last)
			seen[trimmed] = true
			out[len(out)-1] = p
		} else if strings.HasPrefix(last, trimmed) {
			// Current is prefix of last — we already have the complete one, skip
			continue
		} else if !seen[trimmed] {
			seen[trimmed] = true
			out = append(out, p)
		}
	}
	return strings.Join(out, "\n\n")
}

// TaskBridge connects OpenClaw events to the WebSocket Hub,
// routing chat responses to the requesting device for thread isolation
type TaskBridge struct {
	hub                 *websocket.Hub
	client              *Client
	store               *tasks.Store
	skillManager        *skills.Manager
	skillsPath          string // path to skills directory for agent-stop-skill.js
	streamIdleCompleteSec int  // timeout for stream idle before sending complete
	mu                  sync.Mutex
	active              *activeRequest // nil when no request in flight

	lastRunID   string    // tracks the last completed runID to deduplicate trailing final events
	lastRunTime time.Time // tracks when the last run was completed

	// unsolicited maps RunID -> generated UI command_id to group deltas
	unsolicited map[string]string
}

// NewTaskBridge creates a bridge between OpenClaw and the WebSocket Hub
func NewTaskBridge(hub *websocket.Hub, client *Client, store *tasks.Store, skillMgr *skills.Manager, skillsPath string) *TaskBridge {
	// Get stream idle timeout from client config, default to 300 seconds
	streamIdleSec := 300
	if client != nil && client.config != nil {
		streamIdleSec = client.config.StreamIdleCompleteSec
	}

	bridge := &TaskBridge{
		hub:                 hub,
		client:              client,
		store:               store,
		skillManager:        skillMgr,
		skillsPath:          skillsPath,
		streamIdleCompleteSec: streamIdleSec,
		unsolicited:         make(map[string]string),
	}

	// Wire up event handlers
	if client != nil {
		client.OnTaskEvent = bridge.handleTaskEvent
		client.OnChatEvent = bridge.handleChatEvent
		client.OnStreamEvent = bridge.handleStreamEvent
		client.OnStreamComplete = bridge.handleStreamComplete
		client.OnHistoryEvent = bridge.handleHistoryEvent
		client.OnConnected = bridge.handleConnected
		client.OnDisconnected = bridge.handleDisconnected
	}

	return bridge
}

// handleTaskEvent broadcasts task updates to all connected Flutter clients
// and persists to the task store when configured
func (b *TaskBridge) handleTaskEvent(task TaskPush) {
	// Persist to store if available
	if b.store != nil {
		updatedTask, err := b.store.UpdateFromOpenClaw(
			task.Task.ID,
			task.Task.Title,
			task.Task.Description,
			task.Task.Priority,
			task.Task.Status,
			task.Task.Feedback,
			task.Task.Result,
		)
		if err != nil {
			log.Printf("[TaskBridge] Failed to persist task: %v", err)
		}

		// Check if task entered terminal state and has tmux metadata -> trigger cleanup
		if updatedTask != nil && isTerminalStatus(updatedTask.Status) && updatedTask.TmuxPaneId != "" {
			go b.cleanupTmuxForTask(updatedTask)
		}
	}

	data, err := json.Marshal(task)
	if err != nil {
		log.Printf("[TaskBridge] Failed to marshal task: %v", err)
		return
	}

	b.broadcastToAll(data)
	log.Printf("[TaskBridge] Broadcasted task %s: %s → %s",
		task.Action, task.Task.ID, task.Task.Title)
}

// isTerminalStatus returns true if the status is a terminal state (completed, failed, cancelled)
func isTerminalStatus(status string) bool {
	switch status {
	case "completed", "failed", "cancelled":
		return true
	default:
		return false
	}
}

// cleanupTmuxForTask kills the tmux pane for a task without updating status
// (since the task is already in a terminal state)
func (b *TaskBridge) cleanupTmuxForTask(task *tasks.Task) {
	if task.TmuxPaneId == "" {
		return
	}

	log.Printf("[TaskBridge] Cleaning up tmux for task %s (pane: %s)", task.TaskID, task.TmuxPaneId)

	// Find agent-stop-skill.js
	scriptPath := b.findAgentStopScript()
	if scriptPath == "" {
		log.Printf("[TaskBridge] Warning: agent-stop-skill.js not found, cannot cleanup tmux for task %s", task.TaskID)
		return
	}

	// Run agent-stop-skill.js with --force --no-status-update to kill the window immediately
	// (task is already in terminal state, no need for graceful shutdown)
	taskID := task.TaskID
	if taskID == "" {
		taskID = task.ID
	}

	cmd := exec.Command("node", scriptPath, "stop", taskID, "--force", "--no-status-update")
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("[TaskBridge] Failed to cleanup tmux for task %s: %v (output: %s)", taskID, err, string(output))
		return
	}

	log.Printf("[TaskBridge] Successfully cleaned up tmux for task %s", taskID)
}

// findAgentStopScript locates agent-stop-skill.js
func (b *TaskBridge) findAgentStopScript() string {
	// Try skillsPath first
	if b.skillsPath != "" {
		candidate := b.skillsPath + "/software-dev/agent-stop-skill.js"
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
		// Try direct path
		candidate = b.skillsPath + "/agent-stop-skill.js"
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}

	// Fallback: use skillManager to find it via ExecuteSkill mechanism
	// The ExecuteSkill method in skills.go already handles path discovery
	return "" // Will be handled by calling ExecuteSkill if needed
}

func (b *TaskBridge) sendCompleteAndClear(active *activeRequest) {
	if active == nil {
		return
	}
	b.mu.Lock()
	if b.active != active {
		b.mu.Unlock()
		return // already cleared by another path
	}
	// Record the completed runID to deduplicate trailing chat events
	b.lastRunID = active.runID
	b.lastRunTime = time.Now()

	b.active = nil
	if active.timer != nil {
		active.timer.Stop()
	}
	deviceID := active.deviceID
	commandID := active.commandID
	b.mu.Unlock()

	completeMsg := map[string]interface{}{
		"type": "complete",
		"payload": map[string]interface{}{
			"command_id": commandID,
			"status":     "success",
			"result":     map[string]interface{}{"openclaw_done": true},
		},
	}
	if data, err := json.Marshal(completeMsg); err == nil {
		b.hub.SendToDevice(deviceID, data)
	}
	log.Printf("[TaskBridge] Stream complete, cleared active request for %s", deviceID)
}

// sendCompleteAndClearWithError clears the active request and sends an error complete to the device.
func (b *TaskBridge) sendCompleteAndClearWithError(active *activeRequest, errMsg string) {
	if active == nil {
		return
	}
	b.mu.Lock()
	if b.active != active {
		b.mu.Unlock()
		return
	}
	b.lastRunID = active.runID
	b.lastRunTime = time.Now()

	b.active = nil
	if active.timer != nil {
		active.timer.Stop()
	}
	deviceID := active.deviceID
	commandID := active.commandID
	b.mu.Unlock()

	completeMsg := map[string]interface{}{
		"type": "complete",
		"payload": map[string]interface{}{
			"command_id": commandID,
			"status":     "error",
			"error":      errMsg,
		},
	}
	if data, err := json.Marshal(completeMsg); err == nil {
		b.hub.SendToDevice(deviceID, data)
	}
	log.Printf("[TaskBridge] Stream error (%s), cleared active request for %s", errMsg, deviceID)
}

// onStreamIdleTimeout fires when no stream data for streamIdleCompleteSec (fallback)
func (b *TaskBridge) onStreamIdleTimeout() {
	b.mu.Lock()
	active := b.active
	b.mu.Unlock()
	if active != nil {
		log.Printf("[TaskBridge] Stream idle timeout, sending complete")
		b.sendCompleteAndClear(active)
	}
}

// handleStreamComplete is called when OpenClaw sends lifecycle phase "end" or "error".
func (b *TaskBridge) handleStreamComplete() {
	b.mu.Lock()
	active := b.active
	b.mu.Unlock()
	b.sendCompleteAndClear(active)

	// Only broadcast a generic complete when there was no active request (e.g. unsolicited
	// stream); when active was set we already sent device-specific complete and must not
	// broadcast a second one to avoid wrong/duplicate complete for Flutter clients.
	if active == nil {
		msg := map[string]interface{}{
			"type": "complete",
			"payload": map[string]interface{}{
				"command_id": "openclaw_chat",
				"status":     "success",
			},
		}
		if data, err := json.Marshal(msg); err == nil {
			b.hub.Broadcast(data)
		}
	}
}

// handleChatEvent relays agent messages. When there's an active request, marks the turn complete.
// (chat event is an alternative completion signal; lifecycle "end" is primary)
func (b *TaskBridge) handleChatEvent(chat ChatEventPayload) {
	if chat.Message.Role != "assistant" {
		return
	}

	// Extract text from all content blocks; skip tool_call / internal so they don't show as reply
	contentStr := ""
	for _, block := range chat.Message.Content {
		if block.Type == "text" && block.Text != "" && !isToolCallOrInternal(block.Text) {
			contentStr += block.Text
		}
	}
	contentStr = dedupeConsecutiveParagraphs(contentStr)

	b.mu.Lock()
	active := b.active

	log.Printf("[TaskBridge DEBUG] handleChatEvent: state=%s, RunID=%q, lastRunID=%q, timeSince=%v, contentLen=%d",
		chat.State, chat.RunID, b.lastRunID, time.Since(b.lastRunTime), len(contentStr))

	// Quick exit: suppress trailing state="final" ONLY if it carries no significant new text.
	// If it has text (which might happen if deltas were dropped or throttled), we must
	// let it through to handleStreamEvent before completing.
	if chat.State == "final" && chat.RunID != "" && chat.RunID == b.lastRunID && time.Since(b.lastRunTime) < 5*time.Second {
		if contentStr == "" {
			log.Printf("[TaskBridge DEBUG] Suppressing empty final event for RunID=%q", chat.RunID)
			b.mu.Unlock()
			return
		}
		// If there is content, we fall through so we can send one last handleStreamEvent(contentStr)
		// even though active is nil.
	}

	if active != nil && chat.RunID != "" {
		active.runID = chat.RunID // Record the runID
	}
	b.mu.Unlock()

	var cmdID string
	if active != nil {
		cmdID = active.commandID
	} else {
		runId := chat.RunID
		if runId == "" {
			runId = "unknown"
		}
		b.mu.Lock()
		var exists bool
		cmdID, exists = b.unsolicited[runId]
		if !exists {
			cmdID = fmt.Sprintf("unsolicited_%s_%d", runId, time.Now().UnixNano())
			b.unsolicited[runId] = cmdID
		}
		b.mu.Unlock()
	}

	if active != nil {
		if chat.State == "delta" && contentStr != "" {
			// Proxy the cumulative frame to the active device stream
			b.handleStreamEvent(cmdID, contentStr)
		} else if chat.State == "final" {
			// Final may carry the full message (e.g. when gateway sends only final, or final arrives before deltas).
			// Send a last stream update so the bubble has content, then complete.
			if contentStr != "" {
				b.handleStreamEvent(cmdID, contentStr)
			} else {
				log.Printf("[TaskBridge] Chat final for runId=%s has no message content (no deltas or empty final payload)", chat.RunID)
			}
			b.sendCompleteAndClear(active)
		} else if chat.State == "aborted" || chat.State == "error" {
			// Clear active and send error complete so Flutter unblocks.
			b.sendCompleteAndClearWithError(active, chat.State)
		}
	} else {
		// This run was not tied to an active request. Never create a second bubble for a run we
		// already completed (late delta/final after sendCompleteAndClear) — otherwise ID 错乱.
		b.mu.Lock()
		isCompletedRun := chat.RunID != "" && chat.RunID == b.lastRunID
		b.mu.Unlock()
		if isCompletedRun {
			log.Printf("[TaskBridge] Suppressing delta/final for already-completed runId=%q to avoid duplicate bubble", chat.RunID)
			return
		}

		if chat.State == "delta" && contentStr != "" {
			msg := map[string]interface{}{
				"type": "stream",
				"payload": map[string]interface{}{
					"command_id":   cmdID,
					"content":      contentStr,
					"content_type": "text",
				},
			}
			if data, err := json.Marshal(msg); err == nil {
				b.hub.Broadcast(data)
			}
		}

		if chat.State == "final" {
			// Final may carry the full message or missing last bits.
			// Send a last stream update so the bubble has the complete content.
			if contentStr != "" {
				msg := map[string]interface{}{
					"type": "stream",
					"payload": map[string]interface{}{
						"command_id":   cmdID,
						"content":      contentStr,
						"content_type": "text",
					},
				}
				if data, err := json.Marshal(msg); err == nil {
					b.hub.Broadcast(data)
				}
			}

			// Clean up mapping and close the bubble so it doesn't accumulate next time
			b.mu.Lock()
			runId := chat.RunID
			if runId == "" {
				runId = "unknown"
			}
			delete(b.unsolicited, runId)
			b.mu.Unlock()

			completeMsg := map[string]interface{}{
				"type": "complete",
				"payload": map[string]interface{}{
					"command_id": cmdID,
					"status":     "success",
				},
			}
			if cdata, err := json.Marshal(completeMsg); err == nil {
				b.hub.Broadcast(cdata)
			}
		} else if chat.State == "aborted" || chat.State == "error" {
			b.mu.Lock()
			runId := chat.RunID
			if runId == "" {
				runId = "unknown"
			}
			delete(b.unsolicited, runId)
			b.mu.Unlock()

			completeMsg := map[string]interface{}{
				"type": "complete",
				"payload": map[string]interface{}{
					"command_id": cmdID,
					"status":     "error",
					"error":      chat.State,
				},
			}
			if cdata, err := json.Marshal(completeMsg); err == nil {
				b.hub.Broadcast(cdata)
			}
		}
	}
}

// handleHistoryEvent relays the chat.history response payload to Flutter clients
func (b *TaskBridge) handleHistoryEvent(payload []byte) {
	msg := map[string]interface{}{
		"type":    "chat_history",
		"payload": json.RawMessage(payload), // Send the raw array payload directly
	}
	if data, err := json.Marshal(msg); err == nil {
		b.hub.Broadcast(data)
	}
}

// handleStreamEvent routes streaming deltas. When there's an active request, uses
// its commandID and sends only to that device. Resets idle timer on each delta.
func (b *TaskBridge) handleStreamEvent(_, content string) {
	b.mu.Lock()
	active := b.active
	if active == nil {
		b.mu.Unlock()
		return
	}

	// Read all fields and reset timer under the same lock to avoid race
	cmdID := active.commandID
	deviceID := active.deviceID
	if active.timer != nil {
		active.timer.Stop()
	}
	active.timer = time.AfterFunc(time.Duration(b.streamIdleCompleteSec)*time.Second, b.onStreamIdleTimeout)
	b.mu.Unlock()

	msg := map[string]interface{}{
		"type": "stream",
		"payload": map[string]interface{}{
			"command_id":   cmdID,
			"content":      content,
			"content_type": "text",
		},
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	if deviceID != "" {
		b.hub.SendToDevice(deviceID, data)
	} else {
		b.hub.Broadcast(data)
	}
}

// handleConnected logs connection status
func (b *TaskBridge) handleConnected() {
	// Notify Flutter clients that OpenClaw is connected
	msg := map[string]interface{}{
		"type": "openclaw_status",
		"payload": map[string]interface{}{
			"connected": true,
		},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	b.broadcastToAll(data)
	log.Printf("[TaskBridge] OpenClaw connected, notified %d Flutter clients", b.hub.ClientCount())
}

// handleDisconnected logs connection status and clears any active request
func (b *TaskBridge) handleDisconnected(err error) {
	b.mu.Lock()
	active := b.active
	b.active = nil
	b.mu.Unlock()

	// If there was an active request, send error complete so Flutter unblocks
	if active != nil {
		errMsg := ""
		if err != nil {
			errMsg = err.Error()
		} else {
			errMsg = "OpenClaw disconnected"
		}
		completeMsg := map[string]interface{}{
			"type": "complete",
			"payload": map[string]interface{}{
				"command_id": active.commandID,
				"status":     "error",
				"error":      errMsg,
			},
		}
		if data, marshalErr := json.Marshal(completeMsg); marshalErr == nil {
			b.hub.SendToDevice(active.deviceID, data)
		}
	}

	msg := map[string]interface{}{
		"type": "openclaw_status",
		"payload": map[string]interface{}{
			"connected": false,
			"error":     "",
		},
	}
	if err != nil {
		msg["payload"].(map[string]interface{})["error"] = err.Error()
	}
	if data, marshalErr := json.Marshal(msg); marshalErr == nil {
		b.hub.Broadcast(data)
	}
	log.Printf("[TaskBridge] OpenClaw disconnected, notified Flutter clients")
}

// SendTaskToAgent sends a task to the OpenClaw Agent (HTTP-originated, broadcast).
func (b *TaskBridge) SendTaskToAgent(prompt, skill, priority string) (string, error) {
	return b.sendTaskInternal("", "", prompt, skill, priority)
}

// SendTaskToAgentForDevice sends a task and routes responses to the given device only.
// Returns error if another request is in flight (conversation thread isolation).
func (b *TaskBridge) SendTaskToAgentForDevice(deviceID, commandID, prompt, skill, priority string) (string, error) {
	if deviceID == "" || commandID == "" {
		return b.SendTaskToAgent(prompt, skill, priority)
	}
	b.mu.Lock()
	if b.active != nil {
		b.mu.Unlock()
		return "", fmt.Errorf("conversation_busy: 请等待当前对话完成")
	}
	active := &activeRequest{deviceID: deviceID, commandID: commandID}
	active.timer = time.AfterFunc(time.Duration(b.streamIdleCompleteSec)*time.Second, b.onStreamIdleTimeout)
	b.active = active
	b.mu.Unlock()
	return b.sendTaskInternal(deviceID, commandID, prompt, skill, priority)
}

func (b *TaskBridge) sendTaskInternal(deviceID, commandID, prompt, skill, priority string) (string, error) {
	if b.client == nil {
		if deviceID != "" {
			b.mu.Lock()
			b.active = nil
			b.mu.Unlock()
		}
		return "", nil
	}
	if skill != "" && b.skillManager != nil {
		content, err := b.skillManager.ReadContent(skill)
		if err != nil {
			log.Printf("[TaskBridge] Warning: failed to read skill %q: %v", skill, err)
		} else {
			prompt = fmt.Sprintf("<skill_context>\n%s\n</skill_context>\n\n%s", content, prompt)
			log.Printf("[TaskBridge] Prepended skill %q content to prompt", skill)
		}
	}
	reqID, err := b.client.SendTask(prompt, priority)
	if err != nil && deviceID != "" {
		b.mu.Lock()
		b.active = nil
		b.mu.Unlock()
	}
	return reqID, err
}

// ExecuteScheduleSync executes the openclaw-sync-schedule-skill via SkillManager.
// payload: file path (e.g. "data/events/events.json" or "events.json", 事件已统一放入 data/events/)
func (b *TaskBridge) ExecuteScheduleSync(payload string) (string, error) {
	if b.skillManager == nil {
		return "", fmt.Errorf("skill manager not initialized")
	}
	// 技能约定使用 --payload-file=；仅文件名时技能内会到 data/events/ 下解析
	return b.skillManager.ExecuteSkill("openclaw-sync-schedule", "sync", "--payload-file="+payload)
}

// ExecuteAgendaQuery executes the openclaw-agenda-skill
func (b *TaskBridge) ExecuteAgendaQuery(from, to string) (string, error) {
	if b.skillManager == nil {
		return "", fmt.Errorf("skill manager not initialized")
	}
	return b.skillManager.ExecuteSkill("openclaw-agenda", "agenda", "--from="+from, "--to="+to)
}

// broadcastToAll sends a message to all connected Flutter clients
func (b *TaskBridge) broadcastToAll(data []byte) {
	// Use Hub's broadcast mechanism — iterate all clients and send
	// Since Hub doesn't have a broadcast channel, we use GetClient approach
	count := b.hub.ClientCount()
	if count == 0 {
		log.Printf("[TaskBridge] No Flutter clients connected, message queued")
		return
	}

	b.hub.Broadcast(data)
}

// SendChatHistory requests the openclaw gateway for chat history in the main session
func (b *TaskBridge) SendChatHistory(limit int) error {
	if b.client == nil {
		return fmt.Errorf("openclaw client not initialized")
	}
	return b.client.ChatHistory(limit)
}

// SendChatAbort requests the openclaw gateway to abort a chat run in the main session
func (b *TaskBridge) SendChatAbort(runID string) error {
	if b.client == nil {
		return fmt.Errorf("openclaw client not initialized")
	}
	return b.client.ChatAbort(runID)
}

// SendChatHistoryForDevice handles chat history for a specific device (currently broadcasts result)
func (b *TaskBridge) SendChatHistoryForDevice(deviceID string, limit int) error {
	if b.client == nil {
		return fmt.Errorf("openclaw client not initialized")
	}
	// For history, device targeting is slightly complex since the response is async.
	// For now we just trigger the fetch.
	return b.client.ChatHistory(limit)
}

// SendChatAbortForDevice handles abort for a specific device.
func (b *TaskBridge) SendChatAbortForDevice(deviceID, runID string) error {
	if b.client == nil {
		return fmt.Errorf("openclaw client not initialized")
	}

	b.mu.Lock()
	if b.active != nil && b.active.deviceID == deviceID {
		// Stop the timer so it doesn't fire since we are manually aborting
		if b.active.timer != nil {
			b.active.timer.Stop()
		}
		b.active = nil
	}
	b.mu.Unlock()

	return b.client.ChatAbort(runID)
}
