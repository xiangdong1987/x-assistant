package tasks

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// ChatHistoryStore persists chat history to a JSON file
type ChatHistoryStore struct {
	mu       sync.RWMutex
	workDir  string
	filePath string
	data     *chatStoreData
}

type chatStoreData struct {
	Messages []ChatMessage `json:"messages"`
}

type ChatMessage struct {
	ID         string    `json:"id"`
	SessionKey string    `json:"sessionKey"`
	Role       string    `json:"role"`       // "user" or "assistant"
	Content    string    `json:"content"`
	Timestamp  time.Time `json:"timestamp"`
}

// NewChatHistoryStore creates a chat history store with JSON file at workDir/data/chat_history.json
func NewChatHistoryStore(workDir string) (*ChatHistoryStore, error) {
	dataDir := filepath.Join(workDir, "data")
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, fmt.Errorf("create data dir: %w", err)
	}
	filePath := filepath.Join(dataDir, "chat_history.json")

	s := &ChatHistoryStore{
		workDir:  workDir,
		filePath: filePath,
		data:     &chatStoreData{Messages: []ChatMessage{}},
	}
	if err := s.load(); err != nil {
		return s, err
	}
	return s, nil
}

func (s *ChatHistoryStore) load() error {
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

func (s *ChatHistoryStore) save() error {
	raw, err := json.Marshal(s.data)
	if err != nil {
		return err
	}
	return os.WriteFile(s.filePath, raw, 0644)
}

// AddMessage adds a new chat message to history
func (s *ChatHistoryStore) AddMessage(msg *ChatMessage) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Generate ID if not set
	if msg.ID == "" {
		b := make([]byte, 8)
		if _, err := rand.Read(b); err != nil {
			panic("crypto/rand failed: " + err.Error())
		}
		msg.ID = hex.EncodeToString(b)
	}

	// Set timestamp if not set
	if msg.Timestamp.IsZero() {
		msg.Timestamp = time.Now()
	}

	s.data.Messages = append(s.data.Messages, *msg)
	return s.save()
}

// GetAll returns all chat messages sorted by timestamp (newest first)
func (s *ChatHistoryStore) GetAll() []ChatMessage {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]ChatMessage, len(s.data.Messages))
	copy(result, s.data.Messages)

	// Sort by timestamp descending (newest first)
	for i := 0; i < len(result)/2; i++ {
		j := len(result) - 1 - i
		result[i], result[j] = result[j], result[i]
	}

	return result
}

// GetBySession returns messages for a specific session
func (s *ChatHistoryStore) GetBySession(sessionKey string) []ChatMessage {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var result []ChatMessage
	for _, msg := range s.data.Messages {
		if msg.SessionKey == sessionKey {
			result = append(result, msg)
		}
	}
	return result
}

// ClearAll removes all chat history
func (s *ChatHistoryStore) ClearAll() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.data.Messages = []ChatMessage{}
	return s.save()
}

// Count returns the total number of messages
func (s *ChatHistoryStore) Count() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.data.Messages)
}

// GetAllPaginated returns messages with pagination (newest first).
// Returns the page of messages and the total count.
func (s *ChatHistoryStore) GetAllPaginated(offset, limit int) ([]ChatMessage, int) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	total := len(s.data.Messages)
	if total == 0 || offset >= total {
		return nil, total
	}

	// Reverse copy (newest first)
	result := make([]ChatMessage, total)
	for i := 0; i < total; i++ {
		result[i] = s.data.Messages[total-1-i]
	}

	// Apply offset and limit
	end := offset + limit
	if end > total {
		end = total
	}
	return result[offset:end], total
}

// Trim keeps only the most recent maxMessages, removing oldest.
func (s *ChatHistoryStore) Trim(maxMessages int) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.data.Messages) <= maxMessages {
		return nil
	}
	s.data.Messages = s.data.Messages[len(s.data.Messages)-maxMessages:]
	return s.save()
}