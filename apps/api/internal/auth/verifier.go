// Package auth verifies Firebase ID tokens and exposes the caller's identity.
// Identity comes only from a verified token; handlers never accept a client-supplied uid.
package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
)

// Principal is the identity carried by a verified token.
type Principal struct {
	UID      string
	Email    string
	Name     string
	Provider string // firebase.sign_in_provider: google.com, apple.com, password (emulator)
	Expiry   time.Time
}

// Verifier turns a bearer token into a Principal.
type Verifier interface {
	Verify(ctx context.Context, token string) (Principal, error)
}

var ErrInvalidToken = errors.New("invalid token")

// FirebaseJWKSURL serves the public keys Firebase signs ID tokens with.
const FirebaseJWKSURL = "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"

// FirebaseVerifier validates RS256 ID tokens for one Firebase project.
type FirebaseVerifier struct {
	keys   keyfunc.Keyfunc
	parser *jwt.Parser
}

// NewFirebaseVerifier fetches the JWKS (fatal-fast when unreachable), keeps it
// refreshed in the background and returns the verifier. jwksURL may be empty.
func NewFirebaseVerifier(ctx context.Context, projectID, jwksURL string) (*FirebaseVerifier, error) {
	if projectID == "" {
		return nil, errors.New("firebase project id is required")
	}
	if jwksURL == "" {
		jwksURL = FirebaseJWKSURL
	}
	k, err := keyfunc.NewDefaultCtx(ctx, []string{jwksURL})
	if err != nil {
		return nil, fmt.Errorf("jwks: %w", err)
	}
	return &FirebaseVerifier{keys: k, parser: newParser(projectID, "RS256")}, nil
}

func newParser(projectID, method string) *jwt.Parser {
	return jwt.NewParser(
		jwt.WithValidMethods([]string{method}),
		jwt.WithIssuer("https://securetoken.google.com/"+projectID),
		jwt.WithAudience(projectID),
		jwt.WithExpirationRequired(),
		jwt.WithIssuedAt(),
		jwt.WithLeeway(60*time.Second),
	)
}

type claims struct {
	jwt.RegisteredClaims
	Email    string `json:"email"`
	Name     string `json:"name"`
	Firebase struct {
		SignInProvider string `json:"sign_in_provider"`
	} `json:"firebase"`
}

func principalFrom(c claims) (Principal, error) {
	uid := strings.TrimSpace(c.Subject)
	if uid == "" || len(uid) > 128 {
		return Principal{}, ErrInvalidToken
	}
	p := Principal{UID: uid, Email: c.Email, Name: c.Name, Provider: c.Firebase.SignInProvider}
	if c.ExpiresAt != nil {
		p.Expiry = c.ExpiresAt.Time
	}
	return p, nil
}

func (v *FirebaseVerifier) Verify(_ context.Context, token string) (Principal, error) {
	var c claims
	t, err := v.parser.ParseWithClaims(token, &c, v.keys.Keyfunc)
	if err != nil || !t.Valid {
		return Principal{}, ErrInvalidToken
	}
	return principalFrom(c)
}

// BearerToken extracts the token from an Authorization header value.
func BearerToken(header string) (string, bool) {
	const p = "bearer "
	if len(header) > len(p) && strings.EqualFold(header[:len(p)], p) {
		t := strings.TrimSpace(header[len(p):])
		return t, t != ""
	}
	return "", false
}

type ctxKey struct{}

// WithPrincipal stores p in ctx.
func WithPrincipal(ctx context.Context, p Principal) context.Context {
	return context.WithValue(ctx, ctxKey{}, p)
}

// FromContext returns the Principal stored by the auth middleware.
func FromContext(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(ctxKey{}).(Principal)
	return p, ok
}
