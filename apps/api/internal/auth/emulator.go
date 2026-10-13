package auth

import (
	"context"

	"github.com/golang-jwt/jwt/v5"
)

// EmulatorVerifier accepts the UNSIGNED (alg=none) ID tokens the Firebase Auth
// emulator issues, still checking issuer, audience, iat and exp. It is only wired
// up when config allows FIREBASE_AUTH_EMULATOR_HOST (loopback host, non-production
// port), and FirebaseVerifier can never accept alg=none because its parser only
// allows RS256 and golang-jwt refuses "none" unless handed UnsafeAllowNoneSignatureType.
type EmulatorVerifier struct {
	parser *jwt.Parser
}

func NewEmulatorVerifier(projectID string) *EmulatorVerifier {
	return &EmulatorVerifier{parser: newParser(projectID, "none")}
}

func (v *EmulatorVerifier) Verify(_ context.Context, token string) (Principal, error) {
	var c claims
	t, err := v.parser.ParseWithClaims(token, &c, func(*jwt.Token) (any, error) {
		return jwt.UnsafeAllowNoneSignatureType, nil
	})
	if err != nil || !t.Valid {
		return Principal{}, ErrInvalidToken
	}
	return principalFrom(c)
}
