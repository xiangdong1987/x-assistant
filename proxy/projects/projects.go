package projects

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

// Project represents a registered project in the system
type Project struct {
	Key         string   `json:"key"`
	Name        string   `json:"name"`
	Path        string   `json:"path"`
	Type        string   `json:"type,omitempty"`        // backend-service, tool, etc.
	TechStack   []string `json:"techStack,omitempty"`
	Owner       string   `json:"owner,omitempty"`
	Status      string   `json:"status,omitempty"`      // active, archived
	Description string   `json:"description,omitempty"`
	GithubUrl   string   `json:"githubUrl,omitempty"`
}

// Registry manages project configuration
type Registry struct {
	mu         sync.RWMutex
	configPath string
}

// NewRegistry creates a project registry stored under workDir/config/projects.json
func NewRegistry(workDir string) *Registry {
	configDir := filepath.Join(workDir, "config")
	os.MkdirAll(configDir, 0755)
	return &Registry{
		configPath: filepath.Join(configDir, "projects.json"),
	}
}

// GetAll returns all registered projects
func (r *Registry) GetAll() ([]Project, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	data, err := os.ReadFile(r.configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return []Project{}, nil
		}
		return nil, err
	}

	var projects []Project
	if err := json.Unmarshal(data, &projects); err != nil {
		return nil, fmt.Errorf("invalid projects.json: %w", err)
	}
	return projects, nil
}

// Get returns a project by key
func (r *Registry) Get(key string) (*Project, error) {
	projects, err := r.GetAll()
	if err != nil {
		return nil, err
	}
	for _, p := range projects {
		if p.Key == key {
			return &p, nil
		}
	}
	return nil, nil
}

// Set saves the full project list
func (r *Registry) Set(projects []Project) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	data, err := json.MarshalIndent(projects, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(r.configPath, data, 0644)
}

// Upsert adds or updates a project by key
func (r *Registry) Upsert(p Project) error {
	projects, err := r.GetAll()
	if err != nil {
		projects = []Project{}
	}

	found := false
	for i, existing := range projects {
		if existing.Key == p.Key {
			projects[i] = p
			found = true
			break
		}
	}
	if !found {
		projects = append(projects, p)
	}
	return r.Set(projects)
}

// Delete removes a project by key
func (r *Registry) Delete(key string) (bool, error) {
	projects, err := r.GetAll()
	if err != nil {
		return false, err
	}

	for i, p := range projects {
		if p.Key == key {
			projects = append(projects[:i], projects[i+1:]...)
			return true, r.Set(projects)
		}
	}
	return false, nil
}
