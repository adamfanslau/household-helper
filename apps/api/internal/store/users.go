package store

import (
	"context"
	"database/sql"
	"errors"
)

type User struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	Provider    string `json:"provider"`
	CreatedAt   string `json:"created_at"`
	LastSeenAt  string `json:"last_seen_at"`
}

// EnsureUser upserts the caller from a verified token: new fields win when non-empty.
func (db *DB) EnsureUser(ctx context.Context, id, email, name, provider string) error {
	now := Now()
	_, err := db.W.ExecContext(ctx, `INSERT INTO users (id, email, display_name, provider, created_at, last_seen_at)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
		  email        = CASE WHEN excluded.email <> '' THEN excluded.email ELSE users.email END,
		  display_name = CASE WHEN excluded.display_name <> '' THEN excluded.display_name ELSE users.display_name END,
		  provider     = CASE WHEN excluded.provider <> '' THEN excluded.provider ELSE users.provider END,
		  last_seen_at = excluded.last_seen_at`, id, email, name, provider, now, now)
	return err
}

func (db *DB) GetUser(ctx context.Context, id string) (User, error) {
	var u User
	err := db.R.QueryRowContext(ctx, `SELECT id, email, display_name, provider, created_at, last_seen_at FROM users WHERE id = ?`, id).
		Scan(&u.ID, &u.Email, &u.DisplayName, &u.Provider, &u.CreatedAt, &u.LastSeenAt)
	if errors.Is(err, sql.ErrNoRows) {
		return u, ErrNotFound
	}
	return u, err
}
