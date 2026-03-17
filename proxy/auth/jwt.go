package auth

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var jwtSecret []byte

func init() {
	jwtSecret = loadOrCreateSecret()
}

func loadOrCreateSecret() []byte {
	// Try to load from home directory
	homeDir, err := os.UserHomeDir()
	if err != nil {
		log.Println("Warning: could not get home directory, using random secret")
		return generateRandomSecret()
	}

	secretDir := filepath.Join(homeDir, ".claude-voice-proxy")
	secretFile := filepath.Join(secretDir, "jwt.key")

	// Try to read existing secret
	if data, err := os.ReadFile(secretFile); err == nil && len(data) == 32 {
		log.Println("Loaded JWT secret from", secretFile)
		return data
	}

	// Create new secret
	secret := generateRandomSecret()

	// Try to save it
	if err := os.MkdirAll(secretDir, 0700); err == nil {
		if err := os.WriteFile(secretFile, secret, 0600); err == nil {
			log.Println("Saved new JWT secret to", secretFile)
		}
	}

	return secret
}

func generateRandomSecret() []byte {
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		panic("crypto/rand failed: " + err.Error())
	}
	return secret
}

type Claims struct {
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`
	jwt.RegisteredClaims
}

// GenerateToken creates a JWT token for a paired device
func GenerateToken(deviceID, deviceName string) (string, error) {
	claims := Claims{
		DeviceID:   deviceID,
		DeviceName: deviceName,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(30 * 24 * time.Hour)), // 30 days
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "claude-voice-proxy",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(jwtSecret)
}

// ValidateToken verifies and parses a JWT token
func ValidateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtSecret, nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, jwt.ErrSignatureInvalid
}

// GenerateDeviceID creates a unique device identifier
func GenerateDeviceID() string {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		panic("crypto/rand failed: " + err.Error())
	}
	return hex.EncodeToString(bytes)
}
