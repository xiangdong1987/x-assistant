package tasks

import "time"

// Canonical task status values (must match Flutter TaskStatus enum and plan meta sync).
// pending, confirmed, planned, planning, coding, testing, submitting, inProgress, completed, cancelled, failed
const (
	StatusPending    = "pending"
	StatusConfirmed  = "confirmed"
	StatusPlanned    = "planned"
	StatusPlanning   = "planning"
	StatusCoding     = "coding"
	StatusTesting    = "testing"
	StatusSubmitting = "submitting"
	StatusInProgress = "inProgress"
	StatusCompleted  = "completed"
	StatusCancelled  = "cancelled"
	StatusFailed     = "failed"
)

// Task represents a task in the store (compatible with Flutter TaskModel and software-dev-agent-skill)
type Task struct {
	ID          string     `json:"id"`
	TaskID      string     `json:"taskId,omitempty"`   // TASK-YYYYMMDD-NNN for display
	Title       string     `json:"title"`
	Description string     `json:"description,omitempty"`
	Priority    string     `json:"priority"`           // p0, p1, p2, p3
	Status      string     `json:"status"`             // pending, confirmed, planned, planning, coding, testing, submitting, inProgress, completed, cancelled, failed
	Phase       string     `json:"phase,omitempty"`    // plan, code, test, done - for multi-agent workflow
	Source      string     `json:"source"`             // manual, openClaw, cursor
	ProjectKey  string     `json:"projectKey,omitempty"`
	PlanPath    string     `json:"planPath,omitempty"`
	Assignee    string     `json:"assignee,omitempty"`
	CreatedAt   time.Time  `json:"createdAt"`
	UpdatedAt   time.Time  `json:"updatedAt"`
	DueAt       *time.Time `json:"dueAt,omitempty"`
	CompletedAt *time.Time `json:"completedAt,omitempty"`
	Feedback     string     `json:"feedback,omitempty"`
	FeedbackType string     `json:"feedbackType,omitempty"` // done, hasIssue
	Result       string     `json:"result,omitempty"`
	CompletedItems int      `json:"completedItems,omitempty"`
	TotalItems     int      `json:"totalItems,omitempty"`
	// TMUX agent management fields
	Backend         string `json:"backend,omitempty"`
	TmuxSession     string `json:"tmuxSession,omitempty"`
	TmuxWindow      string `json:"tmuxWindow,omitempty"`
	TmuxPaneId      string `json:"tmuxPaneId,omitempty"`
	LastExecLogPath string `json:"lastExecLogPath,omitempty"`
}

// CreateTaskRequest is the body for POST /api/tasks
type CreateTaskRequest struct {
	Title       string  `json:"title"`
	Description string  `json:"description,omitempty"`
	Priority    string  `json:"priority,omitempty"` // p0-p3, default p2
	ProjectKey  string  `json:"projectKey,omitempty"`
	Assignee    string  `json:"assignee,omitempty"`
	DueAt       *string `json:"dueAt,omitempty"`   // ISO 8601
	Source      string  `json:"source,omitempty"`   // manual, skill, auto, openClaw, cursor — 技能创建时传 skill 或 auto
	Backend     string  `json:"backend,omitempty"` // cursor, ccr, claude — 手动创建时用户选择的执行后端
}

// UpdateTaskRequest is the body for PUT /api/tasks/:id
type UpdateTaskRequest struct {
	Title       *string `json:"title,omitempty"`
	Description *string `json:"description,omitempty"`
	Priority    *string `json:"priority,omitempty"`
	Status      *string `json:"status,omitempty"`
	Phase       *string `json:"phase,omitempty"`    // plan, code, test, done
	DueAt       *string `json:"dueAt,omitempty"`
	Feedback    *string `json:"feedback,omitempty"`
	FeedbackType *string `json:"feedbackType,omitempty"`
	TaskID      *string `json:"taskId,omitempty"`
	PlanPath    *string `json:"planPath,omitempty"`
	ProjectKey  *string `json:"projectKey,omitempty"`
	CompletedItems *int `json:"completedItems,omitempty"`
	TotalItems     *int `json:"totalItems,omitempty"`
	// TMUX agent management fields
	Backend         *string `json:"backend,omitempty"`
	TmuxSession     *string `json:"tmuxSession,omitempty"`
	TmuxWindow      *string `json:"tmuxWindow,omitempty"`
	TmuxPaneId      *string `json:"tmuxPaneId,omitempty"`
	LastExecLogPath *string `json:"lastExecLogPath,omitempty"`
}
