package auth

import (
	"crypto/rand"
	"fmt"
	"log"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

type PairingManager struct {
	currentPIN string
	mu         sync.RWMutex
}

func NewPairingManager() *PairingManager {
	return &PairingManager{
		currentPIN: loadOrCreatePIN(),
	}
}

// GeneratePIN returns the persistent 6-digit PIN code.
// It will generate and persist one if it doesn't exist yet.
func (pm *PairingManager) GeneratePIN() string {
	pm.mu.RLock()
	if pm.currentPIN != "" {
		pin := pm.currentPIN
		pm.mu.RUnlock()
		return pin
	}
	pm.mu.RUnlock()

	pm.mu.Lock()
	defer pm.mu.Unlock()

	if pm.currentPIN == "" {
		pm.currentPIN = loadOrCreatePIN()
	}
	return pm.currentPIN
}

// GetCurrentPIN returns the current persistent PIN.
func (pm *PairingManager) GetCurrentPIN() string {
	return pm.GeneratePIN()
}

// VerifyPIN checks if the provided PIN matches the persistent PIN.
func (pm *PairingManager) VerifyPIN(pin string) bool {
	pm.mu.RLock()
	defer pm.mu.RUnlock() // was incorrectly mu.Unlock() – must match RLock

	return pm.currentPIN != "" && pm.currentPIN == pin
}

// ResetPIN generates and persists a new random PIN.
// Returns the new PIN.
func (pm *PairingManager) ResetPIN() string {
	pm.mu.Lock()
	defer pm.mu.Unlock()

	newPin := generateRandomPIN()
	pm.currentPIN = newPin
	savePIN(newPin)
	log.Println("PIN reset successfully")
	return newPin
}

func savePIN(pin string) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	secretDir := filepath.Join(homeDir, ".claude-voice-proxy")
	pinFile := filepath.Join(secretDir, "pairing.pin")

	if err := os.MkdirAll(secretDir, 0700); err != nil {
		return err
	}

	return os.WriteFile(pinFile, []byte(pin), 0600)
}

// SavePIN persists the given 6-digit PIN to disk. Used when starting proxy with -pin flag.
// Call before NewPairingManager so the manager loads this PIN.
func SavePIN(pin string) error {
	pin = strings.TrimSpace(pin)
	if len(pin) != 6 {
		return fmt.Errorf("PIN must be 6 digits, got %d", len(pin))
	}
	for _, c := range pin {
		if c < '0' || c > '9' {
			return fmt.Errorf("PIN must be digits only")
		}
	}
	return savePIN(pin)
}

func loadOrCreatePIN() string {
	// Store alongside JWT secret for consistency
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return generateRandomPIN()
	}

	secretDir := filepath.Join(homeDir, ".claude-voice-proxy")
	pinFile := filepath.Join(secretDir, "pairing.pin")

	// Try to read existing PIN
	if data, err := os.ReadFile(pinFile); err == nil {
		if pin := strings.TrimSpace(string(data)); len(pin) == 6 {
			return pin
		}
	}

	// Create new PIN and persist it
	pin := generateRandomPIN()

	if err := os.MkdirAll(secretDir, 0700); err == nil {
		if err := os.WriteFile(pinFile, []byte(pin), 0600); err == nil {
			log.Println("Saved persistent pairing PIN to", pinFile)
		}
	}

	return pin
}

func generateRandomPIN() string {
	pin := ""
	for i := 0; i < 6; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			panic("crypto/rand failed: " + err.Error())
		}
		pin += n.String()
	}
	return pin
}
