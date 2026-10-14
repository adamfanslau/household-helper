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

	"github.com/adamfanslau/household-helper/apps/api/internal/auth"
	"github.com/adamfanslau/household-helper/apps/api/internal/config"
	"github.com/adamfanslau/household-helper/apps/api/internal/devseed"
	"github.com/adamfanslau/household-helper/apps/api/internal/httpapi"
	"github.com/adamfanslau/household-helper/apps/api/internal/push"
	"github.com/adamfanslau/household-helper/apps/api/internal/sse"
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

	// config already refused the emulator on the production port / a non-loopback host.
	var verifier auth.Verifier
	authMode := "firebase"
	if cfg.EmulatorHost != "" {
		authMode = "emulator"
		verifier = auth.NewEmulatorVerifier(cfg.FirebaseProjectID)
		log.Warn("auth: accepting UNSIGNED tokens from the Firebase Auth emulator", "host", cfg.EmulatorHost, "project", cfg.FirebaseProjectID)
	} else {
		fv, err := auth.NewFirebaseVerifier(ctx, cfg.FirebaseProjectID, "")
		if err != nil {
			return fmt.Errorf("firebase verifier: %w", err)
		}
		verifier = fv
	}
	if cfg.DevSeed {
		if err := devseed.Run(ctx, db, "http://"+cfg.EmulatorHost, cfg.FirebaseProjectID, log); err != nil {
			return fmt.Errorf("dev seed: %w", err)
		}
	}

	hub := sse.New()
	opts := httpapi.Options{DB: db, Log: log, Verifier: verifier, Hub: hub, Version: version, Auth: authMode}
	notifier, err := setupPush(cfg, db, log)
	if err != nil {
		return err
	}
	if notifier != nil {
		defer notifier.Close()
		opts.OnPublish = func(hid string, e sse.Event) {
			notifier.Notify(push.Change{HouseholdID: hid, Table: e.Table, Type: e.Type, Row: e.Row, Actor: e.Actor})
		}
	}
	go prunePushTokens(ctx, db, log)
	handler := httpapi.New(opts)

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

// setupPush builds the FCM notifier, or nil (push disabled) when no service account
// is configured or the file is absent (the VPS env points at /etc/hh-api/fcm-sa.json
// before the key exists).
func setupPush(cfg config.Config, db *store.DB, log *slog.Logger) (*push.Notifier, error) {
	if cfg.FCMServiceAccountFile == "" {
		log.Info("push disabled: FCM_SERVICE_ACCOUNT_FILE not set")
		return nil, nil
	}
	sa, err := push.LoadServiceAccount(cfg.FCMServiceAccountFile)
	if errors.Is(err, os.ErrNotExist) {
		log.Warn("push disabled: service account file not found", "path", cfg.FCMServiceAccountFile)
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("push: %w", err)
	}
	project := cfg.FCMProjectID
	if sa.ProjectID != "" && project != sa.ProjectID {
		log.Warn("push: FCM_PROJECT_ID differs from the service account's project", "configured", project, "key", sa.ProjectID)
	}
	client := push.NewClient(project, push.NewTokenSource(sa, nil), nil)
	log.Info("push enabled", "project", project, "service_account", sa.ClientEmail)
	return push.NewNotifier(push.DBStore{DB: db}, client, log, 0), nil
}

// prunePushTokens drops tokens unseen for 60 days, once at start and then daily.
func prunePushTokens(ctx context.Context, db *store.DB, log *slog.Logger) {
	t := time.NewTicker(24 * time.Hour)
	defer t.Stop()
	for {
		if n, err := db.PrunePushTokens(ctx, 60*24*time.Hour); err != nil {
			if ctx.Err() == nil {
				log.Error("push: prune", "err", err.Error())
			}
		} else if n > 0 {
			log.Info("push: pruned stale tokens", "count", n)
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}
