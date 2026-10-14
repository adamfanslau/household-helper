package push

import (
	"context"
	"strings"

	"github.com/adamfanslau/household-helper/apps/api/internal/store"
)

// DBStore adapts *store.DB to Store.
type DBStore struct{ DB *store.DB }

func (d DBStore) HouseholdPushTokens(ctx context.Context, hid, excludeUID string) ([]Token, error) {
	rows, err := d.DB.HouseholdPushTokens(ctx, hid, excludeUID)
	if err != nil {
		return nil, err
	}
	out := make([]Token, 0, len(rows))
	for _, r := range rows {
		out = append(out, Token{Token: r.Token, Platform: r.Platform})
	}
	return out, nil
}

func (d DBStore) DropPushToken(ctx context.Context, token string) error {
	return d.DB.DropPushToken(ctx, token)
}

// ActorName is the display name, else the email's local part.
func (d DBStore) ActorName(ctx context.Context, uid string) (string, error) {
	u, err := d.DB.GetUser(ctx, uid)
	if err != nil {
		return "", err
	}
	if n := strings.TrimSpace(u.DisplayName); n != "" {
		return n, nil
	}
	if at := strings.Index(u.Email, "@"); at > 0 {
		return u.Email[:at], nil
	}
	return "", nil
}

func (d DBStore) HouseholdName(ctx context.Context, hid string) (string, error) {
	return d.DB.HouseholdName(ctx, hid)
}
