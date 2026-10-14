// Package push sends FCM HTTP v1 notifications straight from Go (no Admin SDK): a
// service-account JWT is exchanged for an OAuth2 access token, messages go to
// fcm.googleapis.com, and a policy decides which committed changes are worth a
// notification. Everything is a no-op when no service account is configured.
package push

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const messagingScope = "https://www.googleapis.com/auth/firebase.messaging"

// ServiceAccount is the subset of a Google service-account JSON key file we use.
type ServiceAccount struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
	ProjectID   string `json:"project_id"`

	key *rsa.PrivateKey
}

// LoadServiceAccount reads and validates the key file.
func LoadServiceAccount(path string) (*ServiceAccount, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return ParseServiceAccount(b)
}

func ParseServiceAccount(b []byte) (*ServiceAccount, error) {
	var sa ServiceAccount
	if err := json.Unmarshal(b, &sa); err != nil {
		return nil, fmt.Errorf("service account: %w", err)
	}
	if sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, errors.New("service account: client_email and private_key are required")
	}
	if sa.TokenURI == "" {
		sa.TokenURI = "https://oauth2.googleapis.com/token"
	}
	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil {
		return nil, errors.New("service account: private_key is not PEM")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		k1, err1 := x509.ParsePKCS1PrivateKey(block.Bytes)
		if err1 != nil {
			return nil, fmt.Errorf("service account: private_key: %w", err)
		}
		key = k1
	}
	rk, ok := key.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("service account: private_key is not RSA")
	}
	sa.key = rk
	return &sa, nil
}

// TokenSource mints and caches OAuth2 access tokens for the messaging scope.
type TokenSource struct {
	sa   *ServiceAccount
	http *http.Client

	mu     sync.Mutex
	token  string
	expiry time.Time
}

func NewTokenSource(sa *ServiceAccount, client *http.Client) *TokenSource {
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	return &TokenSource{sa: sa, http: client}
}

// Token returns a cached access token, refreshing it one minute before expiry.
func (t *TokenSource) Token(ctx context.Context) (string, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.token != "" && time.Now().Before(t.expiry) {
		return t.token, nil
	}
	now := time.Now()
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss":   t.sa.ClientEmail,
		"scope": messagingScope,
		"aud":   t.sa.TokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	}).SignedString(t.sa.key)
	if err != nil {
		return "", fmt.Errorf("sign assertion: %w", err)
	}
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"}, "assertion": {assertion}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, t.sa.TokenURI, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := t.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("token request: %w", err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<16))
	if res.StatusCode != http.StatusOK {
		return "", fmt.Errorf("token request: HTTP %d", res.StatusCode) // body may echo the assertion; never log it
	}
	var tr struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(body, &tr); err != nil || tr.AccessToken == "" {
		return "", errors.New("token request: unexpected response")
	}
	if tr.ExpiresIn <= 0 {
		tr.ExpiresIn = 3600
	}
	t.token = tr.AccessToken
	t.expiry = now.Add(time.Duration(tr.ExpiresIn)*time.Second - time.Minute)
	return t.token, nil
}
