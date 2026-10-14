package store

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

type PushToken struct {
	Token      string
	UserID     string
	Platform   string // ios | android
	CreatedAt  string
	LastSeenAt string
}

// UpsertPushToken registers token for uid; an existing row moves to uid and is marked seen.
func (db *DB) UpsertPushToken(ctx context.Context, token, uid, platform string) error {
	now := Now()
	_, err := db.W.ExecContext(ctx, `INSERT INTO push_tokens (token, user_id, platform, created_at, last_seen_at)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, platform = excluded.platform, last_seen_at = excluded.last_seen_at`,
		token, uid, platform, now, now)
	return err
}

// DeletePushToken removes uid's registration of token (no-op for another user's token).
func (db *DB) DeletePushToken(ctx context.Context, token, uid string) error {
	_, err := db.W.ExecContext(ctx, `DELETE FROM push_tokens WHERE token = ? AND user_id = ?`, token, uid)
	return err
}

// DropPushToken removes token whoever owns it (FCM reported it dead).
func (db *DB) DropPushToken(ctx context.Context, token string) error {
	_, err := db.W.ExecContext(ctx, `DELETE FROM push_tokens WHERE token = ?`, token)
	return err
}

// HouseholdPushTokens returns the tokens of every member of hid except excludeUID.
func (db *DB) HouseholdPushTokens(ctx context.Context, hid, excludeUID string) ([]PushToken, error) {
	rows, err := db.R.QueryContext(ctx, `SELECT p.token, p.user_id, p.platform, p.created_at, p.last_seen_at
		FROM push_tokens p JOIN household_members m ON m.user_id = p.user_id
		WHERE m.household_id = ? AND p.user_id <> ? ORDER BY p.created_at`, hid, excludeUID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PushToken
	for rows.Next() {
		var t PushToken
		if err := rows.Scan(&t.Token, &t.UserID, &t.Platform, &t.CreatedAt, &t.LastSeenAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// PrunePushTokens deletes tokens not seen for maxAge and returns how many went.
func (db *DB) PrunePushTokens(ctx context.Context, maxAge time.Duration) (int64, error) {
	cutoff := time.Now().UTC().Add(-maxAge).Format("2006-01-02T15:04:05.000Z07:00")
	res, err := db.W.ExecContext(ctx, `DELETE FROM push_tokens WHERE last_seen_at < ?`, cutoff)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// HouseholdName is the household's current name ("" when it no longer exists).
func (db *DB) HouseholdName(ctx context.Context, hid string) (string, error) {
	var name string
	err := db.R.QueryRowContext(ctx, `SELECT name FROM households WHERE id = ?`, hid).Scan(&name)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return name, err
}
