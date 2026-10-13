// hh-api is the Household Helper backend: config -> store.Open -> httpapi.New ->
// http.Server, with a graceful SIGTERM shutdown (vps app contract: < 20 s).
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/adamfanslau/household-helper/apps/api/internal/config"
	"github.com/adamfanslau/household-helper/apps/api/internal/httpapi"
	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

// version is set at build time: -ldflags "-X main.version=$GITHUB_SHA".
var version = "dev"

func main() {
	if err := run(); err != nil {
		slog.Error("fatal", "err", err.Error())
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(log)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	db, err := store.Open(ctx, cfg.DBPath)
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}
	defer db.Close()

	authMode := "firebase"
	if cfg.EmulatorHost != "" {
		authMode = "emulator"
		log.Warn("auth: Firebase Auth emulator mode requested (verifier lands in api step B)", "host", cfg.EmulatorHost)
	}
	if cfg.DevSeed {
		log.Warn("DEV_SEED=1: the seed lands in api step B; nothing seeded")
	}

	handler := httpapi.New(httpapi.Options{DB: db, Log: log, Version: version, Auth: authMode})

	addr := net.JoinHostPort(cfg.Host, cfg.Port)
	srv := &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      0, // JSON routes sit in http.TimeoutHandler; SSE must stream
		IdleTimeout:       120 * time.Second,
		ErrorLog:          slog.NewLogLogger(log.Handler(), slog.LevelWarn),
	}
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("listen %s: %w", addr, err)
	}
	log.Info("hh-api listening", "addr", addr, "version", version, "auth", authMode, "dev", cfg.Dev())

	errCh := make(chan error, 1)
	go func() { errCh <- srv.Serve(ln) }()

	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
	}
	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	return nil
}
