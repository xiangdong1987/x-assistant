package projects

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestProjectGithubUrlRoundTrip(t *testing.T) {
	// Verify GithubUrl survives JSON marshal/unmarshal (the root cause of the bug)
	p := Project{
		Key:       "test-proj",
		Name:      "Test Project",
		Path:      "/tmp/test",
		GithubUrl: "https://github.com/example/repo",
	}

	data, err := json.Marshal(p)
	if err != nil {
		t.Fatalf("marshal error: %v", err)
	}

	var decoded Project
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal error: %v", err)
	}

	if decoded.GithubUrl != p.GithubUrl {
		t.Errorf("GithubUrl mismatch: got %q, want %q", decoded.GithubUrl, p.GithubUrl)
	}
}

func TestRegistryUpsertPreservesGithubUrl(t *testing.T) {
	dir := t.TempDir()
	r := &Registry{configPath: filepath.Join(dir, "projects.json")}

	proj := Project{
		Key:       "proj1",
		Name:      "Project One",
		Path:      "/some/path",
		GithubUrl: "https://github.com/org/proj1",
	}

	if err := r.Upsert(proj); err != nil {
		t.Fatalf("upsert error: %v", err)
	}

	// Read raw file to confirm field is persisted
	raw, err := os.ReadFile(r.configPath)
	if err != nil {
		t.Fatalf("read file error: %v", err)
	}
	if !contains(string(raw), "githubUrl") {
		t.Errorf("projects.json does not contain 'githubUrl' key; raw content:\n%s", raw)
	}

	// Re-read through registry
	got, err := r.Get("proj1")
	if err != nil || got == nil {
		t.Fatalf("get error: %v", err)
	}
	if got.GithubUrl != proj.GithubUrl {
		t.Errorf("GithubUrl after re-read: got %q, want %q", got.GithubUrl, proj.GithubUrl)
	}
}

func TestRegistryUpsertUpdatePreservesGithubUrl(t *testing.T) {
	dir := t.TempDir()
	r := &Registry{configPath: filepath.Join(dir, "projects.json")}

	// Insert without githubUrl first
	if err := r.Upsert(Project{Key: "p1", Name: "P1", Path: "/p1"}); err != nil {
		t.Fatalf("initial upsert: %v", err)
	}

	// Update with githubUrl
	updated := Project{Key: "p1", Name: "P1 Updated", Path: "/p1", GithubUrl: "https://github.com/x/y"}
	if err := r.Upsert(updated); err != nil {
		t.Fatalf("update upsert: %v", err)
	}

	got, err := r.Get("p1")
	if err != nil || got == nil {
		t.Fatalf("get: %v", err)
	}
	if got.GithubUrl != updated.GithubUrl {
		t.Errorf("GithubUrl: got %q, want %q", got.GithubUrl, updated.GithubUrl)
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(sub) == 0 ||
		func() bool {
			for i := 0; i <= len(s)-len(sub); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
			return false
		}())
}
