// Package ids generates the identifiers the API mints: UUIDv7 row ids and invite codes.
package ids

import (
	"crypto/rand"

	"github.com/google/uuid"
)

// InviteAlphabet has 32 symbols: no I, O, 0 or 1, so codes survive being read aloud.
const InviteAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

// InviteCodeLen is fixed by the schema CHECK (length(code) = 8).
const InviteCodeLen = 8

// New returns a UUIDv7 string (time-ordered, so created_at order == id order).
func New() string {
	id, err := uuid.NewV7()
	if err != nil {
		return uuid.NewString()
	}
	return id.String()
}

// NewInviteCode returns 8 random symbols from InviteAlphabet (crypto/rand).
func NewInviteCode() string {
	var b [InviteCodeLen]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	out := make([]byte, InviteCodeLen)
	for i, v := range b {
		out[i] = InviteAlphabet[int(v)%len(InviteAlphabet)]
	}
	return string(out)
}

// ValidInviteCode reports whether s has the shape of a code: 8 characters of A-Z or
// 0-9 (after the caller upper-cases it). Lookups are exact, so this accepts codes
// from any generator (the Expo-era hex ones, the seed's MOCK1234), not only InviteAlphabet.
func ValidInviteCode(s string) bool {
	if len(s) != InviteCodeLen {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= 'A' && c <= 'Z') && !(c >= '0' && c <= '9') {
			return false
		}
	}
	return true
}
