// Package config reads the process configuration from the environment.
// The VPS app contract (vps/docs/25-apps.md) requires PORT and DB_PATH; the rest has
// defaults so the binary starts locally with a handful of variables.
//
// Dev-only features (the Firebase Auth emulator verifier, the seed) are refused on the
// production port or on a non-loopback host so they can never be enabled on the VPS.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
)

// ProductionPort is the port reserved for hh-api in the VPS port registry.
const ProductionPort = "8081"

type Config struct {
	Port                  string
	Host                  string
	DBPath                string
	FirebaseProjectID     string
	EmulatorHost          string // FIREBASE_AUTH_EMULATOR_HOST, dev only (host:port)
	DevSeed               bool   // DEV_SEED=1, dev only, needs the emulator
	FCMServiceAccountFile string // empty = push disabled
	FCMProjectID          string // defaults to FirebaseProjectID
	LogLevel              slog.Level
}

func Load() (Config, error) {
	c := Config{
		Port:                  env("PORT", ProductionPort),
		Host:                  env("HOST", "127.0.0.1"),
		DBPath:                env("DB_PATH", ""),
		FirebaseProjectID:     env("FIREBASE_PROJECT_ID", ""),
		EmulatorHost:          env("FIREBASE_AUTH_EMULATOR_HOST", ""),
		DevSeed:               env("DEV_SEED", "") == "1",
		FCMServiceAccountFile: env("FCM_SERVICE_ACCOUNT_FILE", ""),
		FCMProjectID:          env("FCM_PROJECT_ID", ""),
	}
	if c.FCMProjectID == "" {
		c.FCMProjectID = c.FirebaseProjectID
	}
	switch strings.ToLower(env("LOG_LEVEL", "info")) {
	case "debug":
		c.LogLevel = slog.LevelDebug
	case "warn", "warning":
		c.LogLevel = slog.LevelWarn
	case "error":
		c.LogLevel = slog.LevelError
	default:
		c.LogLevel = slog.LevelInfo
	}
	return c, c.validate()
}

// Dev reports whether any dev-only feature is requested.
func (c Config) Dev() bool { return c.EmulatorHost != "" || c.DevSeed }

func (c Config) loopback() bool {
	return c.Host == "127.0.0.1" || c.Host == "localhost" || c.Host == "::1"
}

func (c Config) validate() error {
	var errs []error
	if c.DBPath == "" {
		errs = append(errs, errors.New("DB_PATH is required"))
	}
	if c.FirebaseProjectID == "" {
		errs = append(errs, errors.New("FIREBASE_PROJECT_ID is required"))
	}
	if c.Dev() && c.Port == ProductionPort {
		errs = append(errs, fmt.Errorf("FIREBASE_AUTH_EMULATOR_HOST / DEV_SEED cannot be used with the production port %s", ProductionPort))
	}
	if c.Dev() && !c.loopback() {
		errs = append(errs, errors.New("FIREBASE_AUTH_EMULATOR_HOST / DEV_SEED require HOST=127.0.0.1"))
	}
	if c.DevSeed && c.EmulatorHost == "" {
		errs = append(errs, errors.New("DEV_SEED=1 needs FIREBASE_AUTH_EMULATOR_HOST (the seed creates emulator users)"))
	}
	if c.EmulatorHost != "" && !strings.Contains(c.EmulatorHost, ":") {
		errs = append(errs, errors.New("FIREBASE_AUTH_EMULATOR_HOST must be host:port"))
	}
	return errors.Join(errs...)
}

// env returns the trimmed variable, or def when it is unset or blank (so a
// commented-out line or `KEY=` in .env behaves like "not set").
func env(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}
