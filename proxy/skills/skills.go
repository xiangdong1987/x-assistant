package skills

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
)

const skillFileName = "SKILL.md"

// Skill represents a skill definition
type Skill struct {
	ID   string `json:"id"`   // directory name or filename without .md
	Name string `json:"name"` // from YAML frontmatter "name:" or first # heading
	Path string `json:"path"` // source directory
}

// Manager handles skill path configuration and discovery
type Manager struct {
	mu         sync.RWMutex
	workDir    string // used to resolve relative paths
	configPath string // full path to skill_paths.json
}

// NewManager creates a skills manager that stores config under workDir/config/
func NewManager(workDir string) *Manager {
	configDir := filepath.Join(workDir, "config")
	os.MkdirAll(configDir, 0755)
	return &Manager{
		workDir:    workDir,
		configPath: filepath.Join(configDir, "skill_paths.json"),
	}
}

// GetPaths returns the currently configured skill paths (absolute).
// Paths can come from:
//   - Env XASSISTANT_SKILL_PATHS (colon-separated on Unix, semicolon on Windows), or
//   - skill_paths.json. Entries may be absolute, ~/..., $HOME/..., or relative to workDir.
func (m *Manager) GetPaths() ([]string, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	if env := os.Getenv("XASSISTANT_SKILL_PATHS"); env != "" {
		sep := string(os.PathListSeparator) // ":" on Unix, ";" on Windows
		raw := strings.Split(env, sep)
		out := make([]string, 0, len(raw))
		for _, p := range raw {
			p = strings.TrimSpace(p)
			if p == "" {
				continue
			}
			abs := m.expandPath(p)
			out = append(out, abs)
		}
		return out, nil
	}

	data, err := os.ReadFile(m.configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return []string{}, nil
		}
		return nil, err
	}

	var paths []string
	if err := json.Unmarshal(data, &paths); err != nil {
		return nil, fmt.Errorf("invalid skill_paths.json: %w", err)
	}
	out := make([]string, 0, len(paths))
	for _, p := range paths {
		abs := m.expandPath(p)
		out = append(out, abs)
	}
	return out, nil
}

// expandPath converts a path to absolute: supports ~, $HOME, and relative to m.workDir.
func (m *Manager) expandPath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return path
	}
	// ~ or ~/...
	if strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			path = filepath.Join(home, path[2:])
		}
	} else if path == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			path = home
		}
	} else {
		// $HOME or $WORKDIR
		path = os.ExpandEnv(path)
	}
	// Relative to workDir
	if !filepath.IsAbs(path) {
		path = filepath.Join(m.workDir, path)
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return abs
}

// SetPaths saves the skill paths to config
func (m *Manager) SetPaths(paths []string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	data, err := json.MarshalIndent(paths, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(m.configPath, data, 0644)
}

// DiscoverSkills scans all configured paths and returns skills found.
// It supports two layouts:
//  1. Subdirectory-based: each subdirectory contains a SKILL.md file
//  2. Flat file: each .md file in the top-level directory is a skill (fallback)
func (m *Manager) DiscoverSkills() []Skill {
	paths, err := m.GetPaths()
	if err != nil {
		log.Printf("[Skills] Failed to load paths: %v", err)
		return nil
	}

	var result []Skill
	for _, dir := range paths {
		entries, err := os.ReadDir(dir)
		if err != nil {
			log.Printf("[Skills] Cannot read dir %s: %v", dir, err)
			continue
		}

		for _, entry := range entries {
			if entry.IsDir() {
				// Subdirectory-based skill: look for SKILL.md inside
				skillFile := filepath.Join(dir, entry.Name(), skillFileName)
				if _, err := os.Stat(skillFile); err != nil {
					continue // no SKILL.md, skip
				}

				id := entry.Name()
				name := extractTitle(skillFile)
				if name == "" {
					name = id
				}

				result = append(result, Skill{
					ID:   id,
					Name: name,
					Path: dir,
				})
			} else if strings.HasSuffix(entry.Name(), ".md") {
				// Flat .md file (legacy fallback), skip SKILL.md at top level
				if strings.EqualFold(entry.Name(), skillFileName) {
					continue
				}

				id := strings.TrimSuffix(entry.Name(), ".md")
				name := extractTitle(filepath.Join(dir, entry.Name()))
				if name == "" {
					name = id
				}

				result = append(result, Skill{
					ID:   id,
					Name: name,
					Path: dir,
				})
			}
		}
	}

	return result
}

// ReadContent returns the markdown content of a skill by ID.
// It checks for {id}/SKILL.md first, then falls back to {id}.md.
func (m *Manager) ReadContent(id string) (string, error) {
	paths, err := m.GetPaths()
	if err != nil {
		return "", err
	}

	for _, dir := range paths {
		// Try subdirectory layout first: {dir}/{id}/SKILL.md
		skillPath := filepath.Join(dir, id, skillFileName)
		if data, err := os.ReadFile(skillPath); err == nil {
			return string(data), nil
		}

		// Fallback: {dir}/{id}.md
		flatPath := filepath.Join(dir, id+".md")
		if data, err := os.ReadFile(flatPath); err == nil {
			return string(data), nil
		}
	}

	return "", fmt.Errorf("skill %q not found", id)
}

// extractTitle extracts the skill name from a markdown file.
// It first checks for YAML frontmatter with a "name:" field,
// then falls back to the first "# " heading.
func extractTitle(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	inFrontmatter := false
	firstLine := true

	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		// Check for YAML frontmatter start
		if firstLine && trimmed == "---" {
			inFrontmatter = true
			firstLine = false
			continue
		}
		firstLine = false

		if inFrontmatter {
			// End of frontmatter
			if trimmed == "---" {
				inFrontmatter = false
				continue
			}
			// Look for name: field
			if strings.HasPrefix(trimmed, "name:") {
				name := strings.TrimSpace(strings.TrimPrefix(trimmed, "name:"))
				// Remove surrounding quotes if present
				name = strings.Trim(name, "\"'")
				if name != "" {
					return name
				}
			}
			continue
		}

		// Outside frontmatter: look for first # heading
		if strings.HasPrefix(trimmed, "# ") {
			return strings.TrimSpace(trimmed[2:])
		}
	}
	return ""
}
// ExecuteSkill runs a skill script and returns the HANDOFF JSON.
// It searches each configured path and all its immediate subdirectories.
func (m *Manager) ExecuteSkill(id string, command string, args ...string) (string, error) {
	paths, err := m.GetPaths()
	if err != nil {
		return "", err
	}

	// Build candidate dirs: each configured path + all its immediate subdirectories
	var searchDirs []string
	for _, dir := range paths {
		searchDirs = append(searchDirs, dir)

		// Also walk one level deep so that sibling skill dirs (e.g. schedule/) are found
		entries, readErr := os.ReadDir(dir)
		if readErr == nil {
			for _, entry := range entries {
				if entry.IsDir() {
					searchDirs = append(searchDirs, filepath.Join(dir, entry.Name()))
				}
			}
		}
	}

	var scriptPath string
	for _, dir := range searchDirs {
		// Check {dir}/{id}-skill.js first, then {dir}/{id}.js
		if p := filepath.Join(dir, id+"-skill.js"); fileExists(p) {
			scriptPath = p
			break
		}
		if p := filepath.Join(dir, id+".js"); fileExists(p) {
			scriptPath = p
			break
		}
	}

	if scriptPath == "" {
		return "", fmt.Errorf("skill script for %q not found in %v", id, paths)
	}

	// Run the script via node
	cmdArgs := append([]string{scriptPath, command}, args...)
	cmd := exec.Command("node", cmdArgs...)
	cmd.Dir = filepath.Dir(scriptPath) // run from the script's own directory

	output, err := cmd.CombinedOutput()
	if err != nil {
		return string(output), fmt.Errorf("skill execution failed: %w (output: %s)", err, string(output))
	}

	// Extract HANDOFF: line
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "HANDOFF:") {
			return strings.TrimPrefix(line, "HANDOFF:"), nil
		}
	}

	return "", fmt.Errorf("no HANDOFF output found in skill execution result")
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
