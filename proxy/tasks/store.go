package tasks

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

func generateID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand failed: " + err.Error())
	}
	return hex.EncodeToString(b)
}

// Store persists tasks to a JSON file
type Store struct {
	mu       sync.RWMutex
	workDir  string
	filePath string
	data     *storeData
}

type storeData struct {
	NextSeq int     `json:"nextSeq"`
	Tasks   []*Task `json:"tasks"`
}

// NewStore creates a task store with JSON file at workDir/data/tasks.json
func NewStore(workDir string) (*Store, error) {
	dataDir := filepath.Join(workDir, "data")
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("create data dir: %w", err)
	}
	filePath := filepath.Join(dataDir, "tasks.json")

	s := &Store{
		workDir:  workDir,
		filePath: filePath,
		data:     &storeData{NextSeq: 1, Tasks: []*Task{}},
	}
	if err := s.load(); err != nil {
		return s, err
	}
	return s, nil
}

func (s *Store) load() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	return json.Unmarshal(data, s.data)
}

func (s *Store) save() error {
	// Copy to avoid concurrent modification during marshal
	raw, err := json.Marshal(s.data)
	if err != nil {
		return err
	}
	return os.WriteFile(s.filePath, raw, 0644)
}

// GetAll returns all tasks
func (s *Store) GetAll() ([]*Task, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]*Task, len(s.data.Tasks))
	copy(out, s.data.Tasks)
	return out, nil
}

// GetByID finds a task by id or taskId
func (s *Store) GetByID(idOrTaskID string) (*Task, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, t := range s.data.Tasks {
		if t.ID == idOrTaskID || t.TaskID == idOrTaskID {
			return t, nil
		}
	}
	return nil, nil
}

// ListByStatus returns tasks filtered by status
func (s *Store) ListByStatus(status string) ([]*Task, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var out []*Task
	for _, t := range s.data.Tasks {
		if status == "" || t.Status == status {
			out = append(out, t)
		}
	}
	return out, nil
}

// Create adds a new task
func (s *Store) Create(req *CreateTaskRequest) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	priority := req.Priority
	if priority == "" {
		priority = "p2"
	}

	source := normalizeSource(req.Source)
	task := &Task{
		ID:          generateID(),
		Title:       req.Title,
		Description: req.Description,
		Priority:    priority,
		Status:      StatusPending,
		Source:      source,
		ProjectKey:  req.ProjectKey,
		Assignee:    req.Assignee,
		Backend:     req.Backend,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if req.DueAt != nil && *req.DueAt != "" {
		t, err := time.Parse(time.RFC3339, *req.DueAt)
		if err == nil {
			task.DueAt = &t
		}
	}

	s.data.Tasks = append(s.data.Tasks, task)
	if err := s.save(); err != nil {
		return nil, err
	}
	return task, nil
}

// CreateWithPlan creates a task and generates a plan file in the project's docs/ directory.
// It assigns a TaskID (TASK-YYYYMMDD-NNN) and sets status to "planned".
func (s *Store) CreateWithPlan(req *CreateTaskRequest, projectPath, projectName string, techStack []string) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	priority := req.Priority
	if priority == "" {
		priority = "p2"
	}

	seq := s.data.NextSeq
	s.data.NextSeq++
	taskID := GenerateTaskID(seq)

	source := normalizeSource(req.Source)
	task := &Task{
		ID:          generateID(),
		TaskID:      taskID,
		Title:       req.Title,
		Description: req.Description,
		Priority:    priority,
		Status:      StatusPlanned,
		Source:      source,
		ProjectKey:  req.ProjectKey,
		Assignee:    req.Assignee,
		Backend:     req.Backend,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	// Generate plan file
	vars := PlanTemplateVars{
		TaskID:      taskID,
		TaskTitle:   req.Title,
		ProjectName: projectName,
		ProjectPath: projectPath,
		ProjectKey:  req.ProjectKey,
		TechStack:   techStack,
		Priority:    priority,
		Assignee:    req.Assignee,
		Owner:       req.Assignee,
		Description: req.Description,
	}

	planPath, err := WritePlanToProject(projectPath, taskID, vars)
	if err != nil {
		return nil, fmt.Errorf("write plan: %w", err)
	}
	task.PlanPath = planPath

	s.data.Tasks = append(s.data.Tasks, task)
	if err := s.save(); err != nil {
		return nil, err
	}
	return task, nil
}

// CreateFromOpenClaw creates or updates a task from OpenClaw TaskData
func (s *Store) CreateFromOpenClaw(id, title, description, priority, status, feedback, result string) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	if priority == "" {
		priority = "p1"
	}

	// Check if exists (by OpenClaw id)
	for _, t := range s.data.Tasks {
		if t.ID == id {
			t.Title = title
			t.Description = description
			t.Priority = priority
			t.Status = mapOpenClawStatus(status)
			t.UpdatedAt = now
			if feedback != "" {
				t.Feedback = feedback
			}
			if result != "" {
				t.Result = result
			}
			if mapOpenClawStatus(status) == StatusCompleted {
				t.CompletedAt = &now
			}
			if err := s.save(); err != nil {
				return nil, err
			}
			return t, nil
		}
	}

	task := &Task{
		ID:          id,
		Title:       title,
		Description: description,
		Priority:    priority,
		Status:      mapOpenClawStatus(status),
		Source:      "openClaw",
		Result:      result,
		Feedback:    feedback,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if mapOpenClawStatus(status) == StatusCompleted {
		task.CompletedAt = &now
	}

	s.data.Tasks = append(s.data.Tasks, task)
	if err := s.save(); err != nil {
		return nil, err
	}
	return task, nil
}

// UpdateFromOpenClaw updates task by OpenClaw id (create/update/complete/error)
func (s *Store) UpdateFromOpenClaw(id, title, description, priority, status, feedback, result string) (*Task, error) {
	return s.CreateFromOpenClaw(id, title, description, priority, status, feedback, result)
}

// normalizeSource returns canonical source; "skill" and "auto" mean skill-created, else manual/openClaw/cursor or "manual".
func normalizeSource(s string) string {
	switch strings.TrimSpace(s) {
	case "manual", "openClaw", "cursor", "skill", "auto":
		return s
	default:
		return "manual"
	}
}

// mapOpenClawStatus normalizes OpenClaw status to canonical task status (align with Flutter TaskStatus).
func mapOpenClawStatus(s string) string {
	switch s {
	case StatusInProgress:
		return StatusInProgress
	case StatusCompleted:
		return StatusCompleted
	case StatusPending:
		return StatusPending
	case StatusPlanned:
		return StatusPlanned
	case StatusPlanning, StatusCoding, StatusTesting, StatusSubmitting:
		return s
	case StatusConfirmed:
		return StatusConfirmed
	case StatusCancelled:
		return StatusCancelled
	case StatusFailed:
		return StatusFailed
	case "waitingFeedback":
		return StatusPlanned // legacy compat
	default:
		return s
	}
}

// normalizeTaskStatus returns canonical status or empty if unknown (used to avoid persisting invalid status).
// waitingFeedback is no longer used; legacy value maps to StatusPlanned for backward compat.
func normalizeTaskStatus(s string) string {
	switch strings.TrimSpace(s) {
	case StatusPending:
		return StatusPending
	case StatusConfirmed:
		return StatusConfirmed
	case StatusPlanned:
		return StatusPlanned
	case StatusPlanning, StatusCoding, StatusTesting, StatusSubmitting:
		return strings.TrimSpace(s)
	case StatusInProgress:
		return StatusInProgress
	case "waitingFeedback":
		return StatusPlanned // legacy compat
	case StatusCompleted, "implemented", "done":
		return StatusCompleted
	case StatusCancelled:
		return StatusCancelled
	case StatusFailed:
		return StatusFailed
	default:
		return ""
	}
}

// taskStatusToMetaStatus maps task status to plan meta status for sync
func taskStatusToMetaStatus(taskStatus string) string {
	switch normalizeTaskStatus(taskStatus) {
	case StatusPlanned, StatusPending:
		return "planning"
	case StatusPlanning:
		return "planning"
	case StatusInProgress, StatusCoding:
		return "developing"
	case StatusTesting:
		return "testing"
	case StatusSubmitting:
		return "submitting"
	case StatusCompleted:
		return "implemented"
	case StatusFailed:
		return "failed"
	case StatusCancelled:
		return "cancelled"
	default:
		return ""
	}
}

// metaStatusToTaskStatus maps plan meta status to task status for sync
func metaStatusToTaskStatus(metaStatus string) string {
	s := strings.ToLower(strings.TrimSpace(metaStatus))
	switch s {
	case "planning", "planned":
		return StatusPlanned
	case "developing":
		return StatusCoding
	case "testing":
		return StatusTesting
	case "submitting", "reviewing":
		return StatusSubmitting
	case "implemented", "done", "verified", "completed":
		return StatusCompleted
	case "failed":
		return StatusFailed
	case "cancelled":
		return StatusCancelled
	default:
		return ""
	}
}

// Update applies partial update
func (s *Store) Update(idOrTaskID string, req *UpdateTaskRequest) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	var task *Task
	for _, t := range s.data.Tasks {
		if t.ID == idOrTaskID || t.TaskID == idOrTaskID {
			task = t
			break
		}
	}
	if task == nil {
		return nil, nil
	}

	if req.Title != nil {
		task.Title = *req.Title
	}
	if req.Description != nil {
		task.Description = *req.Description
	}
	if req.Priority != nil {
		task.Priority = *req.Priority
	}
	if req.Status != nil {
		if canonical := normalizeTaskStatus(*req.Status); canonical != "" {
			task.Status = canonical
		}
		if task.Status == StatusCompleted {
			now := time.Now()
			task.CompletedAt = &now
		}
		// Sync task status to plan meta when task has PlanPath
		if task.PlanPath != "" {
			metaStatus := taskStatusToMetaStatus(task.Status)
			if metaStatus != "" {
				_ = UpdatePlanMetaStatus(task.PlanPath, metaStatus)
			}
		}
	}
	if req.Feedback != nil {
		task.Feedback = *req.Feedback
	}
	if req.FeedbackType != nil {
		task.FeedbackType = *req.FeedbackType
	}
	if req.Phase != nil {
		task.Phase = *req.Phase
		// Sync task phase to plan meta when task has PlanPath
		if task.PlanPath != "" {
			_ = UpdatePlanMetaField(task.PlanPath, "phase", *req.Phase)
		}
	}
	if req.TaskID != nil {
		task.TaskID = *req.TaskID
	}
	if req.PlanPath != nil {
		task.PlanPath = *req.PlanPath
	}
	if req.ProjectKey != nil {
		task.ProjectKey = *req.ProjectKey
	}
	if req.DueAt != nil {
		if *req.DueAt == "" {
			task.DueAt = nil
		} else {
			t, err := time.Parse(time.RFC3339, *req.DueAt)
			if err == nil {
				task.DueAt = &t
			}
		}
	}
	if req.CompletedItems != nil {
		if *req.CompletedItems < 0 {
			task.CompletedItems = 0
		} else {
			task.CompletedItems = *req.CompletedItems
		}
	}
	if req.TotalItems != nil {
		if *req.TotalItems < 0 {
			task.TotalItems = 0
		} else {
			task.TotalItems = *req.TotalItems
		}
	}
	// Ensure progress stays within valid bounds when both fields are set
	if task.TotalItems > 0 && task.CompletedItems > task.TotalItems {
		task.CompletedItems = task.TotalItems
	}
	// TMUX agent management fields
	if req.Backend != nil {
		task.Backend = *req.Backend
	}
	if req.TmuxSession != nil {
		task.TmuxSession = *req.TmuxSession
	}
	if req.TmuxWindow != nil {
		task.TmuxWindow = *req.TmuxWindow
	}
	if req.TmuxPaneId != nil {
		task.TmuxPaneId = *req.TmuxPaneId
	}
	if req.LastExecLogPath != nil {
		task.LastExecLogPath = *req.LastExecLogPath
	}
	task.UpdatedAt = time.Now()

	if err := s.save(); err != nil {
		return nil, err
	}
	return task, nil
}

// Delete removes a task
func (s *Store) Delete(idOrTaskID string) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	for i, t := range s.data.Tasks {
		if t.ID == idOrTaskID || t.TaskID == idOrTaskID {
			s.data.Tasks = append(s.data.Tasks[:i], s.data.Tasks[i+1:]...)
			return true, s.save()
		}
	}
	return false, nil
}

// SyncTaskStatus syncs plan meta status to task status for all tasks with PlanPath.
// It parses the plan meta and updates the task when meta status differs from task status.
func (s *Store) SyncTaskStatus(notify func(action string, task *Task)) {
	tasksToSync, _ := s.GetAll()

	for _, t := range tasksToSync {
		if t.PlanPath == "" {
			continue
		}

		changed := false
		updateReq := &UpdateTaskRequest{}

		// Parse progress (completedItems, totalItems)
		completed, total := ParsePlanProgress(t.PlanPath)
		if completed != t.CompletedItems || total != t.TotalItems {
			changed = true
			updateReq.CompletedItems = &completed
			updateReq.TotalItems = &total
		}

		// Parse meta status and phase, sync to task
		meta := ParsePlanMeta(t.PlanPath)
		if meta != nil {
			if metaSt, ok := meta["status"]; ok && metaSt != "" {
				taskSt := metaStatusToTaskStatus(metaSt)
				if taskSt != "" && taskSt != t.Status {
					changed = true
					updateReq.Status = &taskSt
				}
			}
			// Sync phase from plan meta to task
			if metaPhase, ok := meta["phase"]; ok && metaPhase != "" {
				if metaPhase != t.Phase {
					changed = true
					updateReq.Phase = &metaPhase
				}
			}
		}

		if changed {
			updatedTask, err := s.Update(t.ID, updateReq)
			if err == nil && updatedTask != nil && notify != nil {
				notify("update", updatedTask)
			}
		}
	}
}
