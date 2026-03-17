package tasks

import (
	"encoding/json"
	"net/http"
	"strings"

	"claude-voice-proxy/auth"
)

// Handlers provides HTTP handlers for the task API
type Handlers struct {
	Store        *Store
	OnTaskUpdate func(action string, task *Task)
}

func (h *Handlers) notify(action string, task *Task) {
	if h.OnTaskUpdate != nil && task != nil {
		h.OnTaskUpdate(action, task)
	}
}

// RequireAuth is middleware that validates JWT from Authorization header or ?token=
func RequireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("token")
		if token == "" {
			authHeader := r.Header.Get("Authorization")
			if strings.HasPrefix(authHeader, "Bearer ") {
				token = strings.TrimPrefix(authHeader, "Bearer ")
			}
		}
		if token == "" {
			w.WriteHeader(http.StatusUnauthorized)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"error": "missing token (Authorization: Bearer <token> or ?token=)",
			})
			return
		}
		_, err := auth.ValidateToken(token)
		if err != nil {
			w.WriteHeader(http.StatusUnauthorized)
			json.NewEncoder(w).Encode(map[string]interface{}{
				"error": "invalid token",
			})
			return
		}
		next.ServeHTTP(w, r)
	}
}

// ListTasks handles GET /api/tasks
func (h *Handlers) ListTasks(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	var tasks []*Task
	var err error
	if status != "" {
		tasks, err = h.Store.ListByStatus(status)
	} else {
		tasks, err = h.Store.GetAll()
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]interface{}{
		"tasks": tasks,
		"total": len(tasks),
	})
}

// GetTask handles GET /api/tasks/:id
func (h *Handlers) GetTask(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	if id == "" {
		http.Error(w, "task id required", http.StatusBadRequest)
		return
	}
	task, err := h.Store.GetByID(id)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if task == nil {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "task not found"})
		return
	}
	json.NewEncoder(w).Encode(task)
}

// CreateTask handles POST /api/tasks
func (h *Handlers) CreateTask(w http.ResponseWriter, r *http.Request) {
	var req CreateTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if req.Title == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "title is required"})
		return
	}
	task, err := h.Store.Create(&req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	h.notify("create", task)
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(task)
}

// UpdateTask handles PUT /api/tasks/:id
func (h *Handlers) UpdateTask(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	if id == "" {
		http.Error(w, "task id required", http.StatusBadRequest)
		return
	}
	var req UpdateTaskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	task, err := h.Store.Update(id, &req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if task == nil {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "task not found"})
		return
	}
	action := "update"
	if task.Status == StatusCompleted {
		action = "complete"
	} else if task.Status == StatusFailed {
		action = "error"
	}
	h.notify(action, task)
	json.NewEncoder(w).Encode(task)
}

// DeleteTask handles DELETE /api/tasks/:id
func (h *Handlers) DeleteTask(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/tasks/")
	if id == "" {
		http.Error(w, "task id required", http.StatusBadRequest)
		return
	}
	ok, err := h.Store.Delete(id)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": "task not found"})
		return
	}
	// Note: Store.Delete doesn't return the deleted task, so we construct a minimal one for the notification
	h.notify("delete", &Task{ID: id})
	w.WriteHeader(http.StatusNoContent)
}
