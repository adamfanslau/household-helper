package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"

	"github.com/adamfanslau/household-helper/apps/api/internal/ids"
)

type Household struct {
	ID        string  `json:"id"`
	Name      string  `json:"name"`
	CreatedBy *string `json:"created_by"`
	CreatedAt string  `json:"created_at"`
	UpdatedAt string  `json:"updated_at"`
	Role      string  `json:"role,omitempty"` // the caller's membership role, when queried as a member
}

type Invite struct {
	ID          string  `json:"id"`
	HouseholdID string  `json:"household_id"`
	Code        string  `json:"code"`
	CreatedBy   *string `json:"created_by"`
	CreatedAt   string  `json:"created_at"`
	ExpiresAt   *string `json:"expires_at"`
	RevokedAt   *string `json:"revoked_at"`
}

type Member struct {
	HouseholdID string `json:"household_id"`
	UserID      string `json:"user_id"`
	Role        string `json:"role"`
	JoinedAt    string `json:"joined_at"`
}

const householdCols = `h.id, h.name, h.created_by, h.created_at, h.updated_at`

func scanHousehold(row interface{ Scan(...any) error }, withRole bool) (Household, error) {
	var h Household
	var createdBy sql.NullString
	var err error
	if withRole {
		err = row.Scan(&h.ID, &h.Name, &createdBy, &h.CreatedAt, &h.UpdatedAt, &h.Role)
	} else {
		err = row.Scan(&h.ID, &h.Name, &createdBy, &h.CreatedAt, &h.UpdatedAt)
	}
	h.CreatedBy = ptrS(createdBy)
	return h, err
}

// CreateHousehold makes the household, adds uid as owner and mints the first
// invite, in one transaction (the Postgres create_household() RPC).
func (db *DB) CreateHousehold(ctx context.Context, uid, name string) (Household, error) {
	now := Now()
	h := Household{ID: ids.New(), Name: name, CreatedBy: &uid, CreatedAt: now, UpdatedAt: now, Role: "owner"}
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `INSERT INTO households (id, name, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`,
			h.ID, h.Name, uid, now, now); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO household_members (household_id, user_id, role, joined_at) VALUES (?, ?, 'owner', ?)`,
			h.ID, uid, now); err != nil {
			return err
		}
		_, err := insertInvite(ctx, tx, h.ID, uid)
		return err
	})
	return h, err
}

// insertInvite mints a code, retrying on the (astronomically unlikely) UNIQUE collision.
func insertInvite(ctx context.Context, tx querier, hid, uid string) (Invite, error) {
	for attempt := 0; attempt < 5; attempt++ {
		inv := Invite{ID: ids.New(), HouseholdID: hid, Code: ids.NewInviteCode(), CreatedBy: &uid, CreatedAt: Now()}
		_, err := tx.ExecContext(ctx, `INSERT INTO household_invites (id, household_id, code, created_by, created_at) VALUES (?, ?, ?, ?, ?)`,
			inv.ID, inv.HouseholdID, inv.Code, uid, inv.CreatedAt)
		if err == nil {
			return inv, nil
		}
		if !strings.Contains(err.Error(), "UNIQUE") {
			return Invite{}, err
		}
	}
	return Invite{}, ErrConflict
}

// ListHouseholds returns the households uid belongs to, oldest first, with the role.
func (db *DB) ListHouseholds(ctx context.Context, uid string) ([]Household, error) {
	rows, err := db.R.QueryContext(ctx, `SELECT `+householdCols+`, m.role FROM households h
		JOIN household_members m ON m.household_id = h.id WHERE m.user_id = ? ORDER BY h.created_at, h.id`, uid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Household{}
	for rows.Next() {
		h, err := scanHousehold(rows, true)
		if err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}

// GetHousehold returns hid as seen by uid: ErrNotFound unless uid is a member,
// so non-members cannot tell whether a household exists.
func (db *DB) GetHousehold(ctx context.Context, hid, uid string) (Household, error) {
	h, err := scanHousehold(db.R.QueryRowContext(ctx, `SELECT `+householdCols+`, m.role FROM households h
		JOIN household_members m ON m.household_id = h.id WHERE h.id = ? AND m.user_id = ?`, hid, uid), true)
	if errors.Is(err, sql.ErrNoRows) {
		return h, ErrNotFound
	}
	return h, err
}

// IsMember is the requireMember check.
func (db *DB) IsMember(ctx context.Context, hid, uid string) (bool, error) {
	var n int
	err := db.R.QueryRowContext(ctx, `SELECT COUNT(*) FROM household_members WHERE household_id = ? AND user_id = ?`, hid, uid).Scan(&n)
	return n > 0, err
}

func (db *DB) UpdateHouseholdName(ctx context.Context, hid, uid, name string) (Household, error) {
	res, err := db.W.ExecContext(ctx, `UPDATE households SET name = ?, updated_at = ? WHERE id = ?`, name, Now(), hid)
	if err != nil {
		return Household{}, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return Household{}, ErrNotFound
	}
	return db.GetHousehold(ctx, hid, uid)
}

// JoinHousehold validates an invite code and adds uid as a member (idempotent),
// returning the household so the client can select it (the Expo app never did).
func (db *DB) JoinHousehold(ctx context.Context, uid, code string) (Household, error) {
	var hid string
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx, `SELECT household_id FROM household_invites
			WHERE code = ? AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > ?)`, code, Now()).Scan(&hid)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO household_members (household_id, user_id, role, joined_at) VALUES (?, ?, 'member', ?)
			ON CONFLICT(household_id, user_id) DO NOTHING`, hid, uid, Now())
		return err
	})
	if err != nil {
		return Household{}, err
	}
	return db.GetHousehold(ctx, hid, uid)
}

func (db *DB) ListMembers(ctx context.Context, hid string) ([]Member, error) {
	rows, err := db.R.QueryContext(ctx, `SELECT household_id, user_id, role, joined_at FROM household_members WHERE household_id = ? ORDER BY joined_at`, hid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Member{}
	for rows.Next() {
		var m Member
		if err := rows.Scan(&m.HouseholdID, &m.UserID, &m.Role, &m.JoinedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

const inviteCols = `id, household_id, code, created_by, created_at, expires_at, revoked_at`

func scanInvite(row interface{ Scan(...any) error }) (Invite, error) {
	var i Invite
	var createdBy, expires, revoked sql.NullString
	err := row.Scan(&i.ID, &i.HouseholdID, &i.Code, &createdBy, &i.CreatedAt, &expires, &revoked)
	i.CreatedBy, i.ExpiresAt, i.RevokedAt = ptrS(createdBy), ptrS(expires), ptrS(revoked)
	return i, err
}

// ListInvites returns a household's invites, newest first (clients show the newest unrevoked one).
func (db *DB) ListInvites(ctx context.Context, hid string) ([]Invite, error) {
	rows, err := db.R.QueryContext(ctx, `SELECT `+inviteCols+` FROM household_invites WHERE household_id = ? ORDER BY created_at DESC, id DESC`, hid)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Invite{}
	for rows.Next() {
		i, err := scanInvite(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, i)
	}
	return out, rows.Err()
}

func (db *DB) CreateInvite(ctx context.Context, hid, uid string) (Invite, error) {
	var inv Invite
	err := db.Tx(ctx, func(tx *sql.Tx) error {
		var err error
		inv, err = insertInvite(ctx, tx, hid, uid)
		return err
	})
	return inv, err
}

// RevokeInvite marks the invite revoked; scoped to hid so a member cannot revoke another household's code.
func (db *DB) RevokeInvite(ctx context.Context, hid, id string) (Invite, error) {
	res, err := db.W.ExecContext(ctx, `UPDATE household_invites SET revoked_at = ? WHERE id = ? AND household_id = ? AND revoked_at IS NULL`, Now(), id, hid)
	if err != nil {
		return Invite{}, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return Invite{}, ErrNotFound
	}
	inv, err := scanInvite(db.R.QueryRowContext(ctx, `SELECT `+inviteCols+` FROM household_invites WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return inv, ErrNotFound
	}
	return inv, err
}
