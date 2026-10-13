package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/MicahParks/jwkset"
	"github.com/golang-jwt/jwt/v5"
)

func baseClaims(iss, aud string, exp time.Duration) claims {
	c := claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer: iss, Audience: jwt.ClaimStrings{aud}, Subject: "uid-1",
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(exp)), IssuedAt: jwt.NewNumericDate(time.Now()),
		},
		Email: "a@b.c", Name: "A",
	}
	c.Firebase.SignInProvider = "google.com"
	return c
}

// noneToken builds an alg=none token the way the Auth emulator does (empty signature).
func noneToken(t *testing.T, c claims) string {
	t.Helper()
	s, err := jwt.NewWithClaims(jwt.SigningMethodNone, c).SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestFirebaseVerifierAgainstFakeJWKS(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	jwk, err := jwkset.NewJWKFromKey(key.Public(), jwkset.JWKOptions{Metadata: jwkset.JWKMetadataOptions{KID: "k1", ALG: jwkset.AlgRS256, USE: jwkset.UseSig}})
	if err != nil {
		t.Fatal(err)
	}
	set := jwkset.JWKSMarshal{Keys: []jwkset.JWKMarshal{jwk.Marshal()}}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(set)
	}))
	defer srv.Close()

	v, err := NewFirebaseVerifier(context.Background(), "proj", srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	mk := func(iss, aud string, exp time.Duration) string {
		tok := jwt.NewWithClaims(jwt.SigningMethodRS256, baseClaims(iss, aud, exp))
		tok.Header["kid"] = "k1"
		s, err := tok.SignedString(key)
		if err != nil {
			t.Fatal(err)
		}
		return s
	}
	p, err := v.Verify(context.Background(), mk("https://securetoken.google.com/proj", "proj", time.Hour))
	if err != nil || p.UID != "uid-1" || p.Email != "a@b.c" || p.Provider != "google.com" {
		t.Fatalf("valid token rejected: %v %+v", err, p)
	}
	if _, err := v.Verify(context.Background(), mk("https://securetoken.google.com/other", "proj", time.Hour)); err == nil {
		t.Fatal("wrong issuer accepted")
	}
	if _, err := v.Verify(context.Background(), mk("https://securetoken.google.com/proj", "other", time.Hour)); err == nil {
		t.Fatal("wrong audience accepted")
	}
	if _, err := v.Verify(context.Background(), mk("https://securetoken.google.com/proj", "proj", -2*time.Hour)); err == nil {
		t.Fatal("expired token accepted")
	}
	if _, err := v.Verify(context.Background(), "garbage"); err == nil {
		t.Fatal("garbage accepted")
	}
	// The production verifier must never accept an unsigned emulator-style token.
	if _, err := v.Verify(context.Background(), noneToken(t, baseClaims("https://securetoken.google.com/proj", "proj", time.Hour))); err == nil {
		t.Fatal("alg=none accepted by the Firebase verifier")
	}
}

func TestEmulatorVerifier(t *testing.T) {
	v := NewEmulatorVerifier("demo-household-helper")
	good := baseClaims("https://securetoken.google.com/demo-household-helper", "demo-household-helper", time.Hour)
	good.Firebase.SignInProvider = "password"
	p, err := v.Verify(context.Background(), noneToken(t, good))
	if err != nil || p.UID != "uid-1" || p.Provider != "password" {
		t.Fatalf("emulator token rejected: %v %+v", err, p)
	}
	if _, err := v.Verify(context.Background(), noneToken(t, baseClaims("https://securetoken.google.com/demo-household-helper", "other", time.Hour))); err == nil {
		t.Fatal("wrong audience accepted")
	}
	if _, err := v.Verify(context.Background(), noneToken(t, baseClaims("https://securetoken.google.com/other", "demo-household-helper", time.Hour))); err == nil {
		t.Fatal("wrong issuer accepted")
	}
	if _, err := v.Verify(context.Background(), noneToken(t, baseClaims("https://securetoken.google.com/demo-household-helper", "demo-household-helper", -2*time.Hour))); err == nil {
		t.Fatal("expired accepted")
	}
	// An RS256 token (even one the emulator parser could decode) is not accepted here either.
	key, _ := rsa.GenerateKey(rand.Reader, 2048)
	signed, _ := jwt.NewWithClaims(jwt.SigningMethodRS256, good).SignedString(key)
	if _, err := v.Verify(context.Background(), signed); err == nil {
		t.Fatal("RS256 accepted by the emulator verifier")
	}
	if _, err := v.Verify(context.Background(), "garbage"); err == nil {
		t.Fatal("garbage accepted")
	}
}

func TestBearer(t *testing.T) {
	if tok, ok := BearerToken("Bearer abc"); !ok || tok != "abc" {
		t.Fatal("bearer parse")
	}
	if _, ok := BearerToken("Basic abc"); ok {
		t.Fatal("basic accepted")
	}
	if _, ok := BearerToken("Bearer "); ok {
		t.Fatal("empty accepted")
	}
}
