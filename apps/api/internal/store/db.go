// Package store owns the SQLite database: one single-connection writer pool (every
// write tx is BEGIN IMMEDIATE), a small reader pool, embedded migrations and the
// per-table queries. Same shape as rounds/api/internal/store.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"time"

	"github.com/adamfanslau/household-helper/apps/api/internal/ids"
	_ "modernc.org/sqlite"
)

var (
	ErrNotFound = errors.New("not found")
	ErrConflict = errors.New("conflict")
	// ErrInvalid is a reference that is well-formed but not allowed, e.g. a shop
	// from another household; handlers map it to 400 with a field message.
	ErrInvalid = errors.New("invalid reference")
)

// Opt is an optional, nullable string for PATCH bodies: Set=false means "leave
// as is", Set=true with Value=nil means "clear".
type Opt struct {
	Set   bool
	Value *string
}

// DB holds the writer and reader pools.
type DB struct {
	W *sql.DB
	R *sql.DB
}

// Open opens (creating if needed) the database at path and applies migrations.
func Open(ctx context.Context, path string) (*DB, error) {
	db, err := openNoMigrate(ctx, path)
	if err != nil {
		return nil, err
	}
	if err := db.Migrate(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return db, nil
}

// openNoMigrate opens the pools without touching the schema (tests build older schemas).
func openNoMigrate(ctx context.Context, path string) (*DB, error) {
	dsn := func(txlock string) string {
		q := url.Values{}
		q.Add("_pragma", "busy_timeout(5000)")
		q.Add("_pragma", "journal_mode(WAL)")
		q.Add("_pragma", "foreign_keys(1)")
		q.Add("_pragma", "synchronous(NORMAL)")
		if txlock != "" {
			q.Set("_txlock", txlock)
		}
		return "file:" + path + "?" + q.Encode()
	}
	w, err := sql.Open("sqlite", dsn("immediate"))
	if err != nil {
		return nil, err
	}
	w.SetMaxOpenConns(1)
	w.SetConnMaxLifetime(0)
	r, err := sql.Open("sqlite", dsn(""))
	if err != nil {
		w.Close()
		return nil, err
	}
	r.SetMaxOpenConns(4)
	r.SetConnMaxLifetime(0)
	db := &DB{W: w, R: r}
	if err := db.Ping(ctx); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

// Ping runs SELECT 1 on both pools.
func (db *DB) Ping(ctx context.Context) error {
	for _, p := range []*sql.DB{db.W, db.R} {
		var one int
		if err := p.QueryRowContext(ctx, "SELECT 1").Scan(&one); err != nil {
			return err
		}
	}
	return nil
}

func (db *DB) Close() error {
	return errors.Join(db.W.Close(), db.R.Close())
}

// Tx runs fn inside one immediate write transaction.
func (db *DB) Tx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := db.W.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// NewID returns a UUIDv7 string.
func NewID() string { return ids.New() }

// Now returns the current time as an RFC 3339 UTC string with milliseconds.
func Now() string {
	return time.Now().UTC().Format("2006-01-02T15:04:05.000Z07:00")
}

// querier is satisfied by *sql.DB and *sql.Tx.
type querier interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

func nullStr(p *string) any {
	if p == nil {
		return nil
	}
	return *p
}

func ptrS(n sql.NullString) *string {
	if !n.Valid {
		return nil
	}
	s := n.String
	return &s
}
