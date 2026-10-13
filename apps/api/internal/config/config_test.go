package config

import (
	"strings"
	"testing"
)

func base(t *testing.T) {
	t.Helper()
	t.Setenv("DB_PATH", "x.db")
	t.Setenv("FIREBASE_PROJECT_ID", "demo-household-helper")
	t.Setenv("PORT", "8091")
	t.Setenv("HOST", "127.0.0.1")
	t.Setenv("FIREBASE_AUTH_EMULATOR_HOST", "")
	t.Setenv("DEV_SEED", "")
}

func mustFail(t *testing.T, want string) {
	t.Helper()
	_, err := Load()
	if err == nil || !strings.Contains(err.Error(), want) {
		t.Fatalf("expected error containing %q, got %v", want, err)
	}
}

func TestProductionDefaults(t *testing.T) {
	base(t)
	t.Setenv("PORT", "")
	c, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if c.Port != ProductionPort || c.Dev() || c.FCMProjectID != "demo-household-helper" {
		t.Fatalf("unexpected config %+v", c)
	}
}

func TestRequired(t *testing.T) {
	base(t)
	t.Setenv("DB_PATH", "")
	mustFail(t, "DB_PATH")
	base(t)
	t.Setenv("FIREBASE_PROJECT_ID", "")
	mustFail(t, "FIREBASE_PROJECT_ID")
}

func TestDevGuards(t *testing.T) {
	base(t)
	t.Setenv("FIREBASE_AUTH_EMULATOR_HOST", "127.0.0.1:9099")
	t.Setenv("DEV_SEED", "1")
	if c, err := Load(); err != nil || !c.Dev() || !c.DevSeed {
		t.Fatalf("dev config on 8091/loopback should load: %v", err)
	}
	t.Setenv("PORT", ProductionPort)
	mustFail(t, "production port")

	base(t)
	t.Setenv("FIREBASE_AUTH_EMULATOR_HOST", "127.0.0.1:9099")
	t.Setenv("HOST", "0.0.0.0")
	mustFail(t, "HOST=127.0.0.1")

	base(t)
	t.Setenv("DEV_SEED", "1")
	mustFail(t, "needs FIREBASE_AUTH_EMULATOR_HOST")

	base(t)
	t.Setenv("FIREBASE_AUTH_EMULATOR_HOST", "localhost")
	mustFail(t, "host:port")
}
