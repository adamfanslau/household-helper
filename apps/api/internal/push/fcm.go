package push

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

// ErrUnregistered means FCM will never deliver to this token again: delete it.
var ErrUnregistered = errors.New("token unregistered")

// Message is one notification to one device token.
type Message struct {
	Token       string
	Title       string
	Body        string
	HouseholdID string
	Type        string // shopping_list_items.insert | household_members.insert
}

// Sender delivers a Message; the Notifier only needs this.
type Sender interface {
	Send(ctx context.Context, m Message) error
}

// Client talks to the FCM HTTP v1 API.
type Client struct {
	endpoint string // https://fcm.googleapis.com/v1/projects/<id>/messages:send
	tokens   *TokenSource
	http     *http.Client
}

func NewClient(projectID string, tokens *TokenSource, client *http.Client) *Client {
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	return &Client{endpoint: "https://fcm.googleapis.com/v1/projects/" + projectID + "/messages:send", tokens: tokens, http: client}
}

// WithEndpoint overrides the send URL (tests).
func (c *Client) WithEndpoint(u string) *Client { c.endpoint = u; return c }

// payload is the FCM v1 message shape; collapse keys fold bursts per household on
// both platforms and thread-id groups the banners on iOS.
func payload(m Message) map[string]any {
	collapse := "hh-" + m.HouseholdID
	return map[string]any{
		"message": map[string]any{
			"token":        m.Token,
			"notification": map[string]string{"title": m.Title, "body": m.Body},
			"data":         map[string]string{"household_id": m.HouseholdID, "type": m.Type},
			"android": map[string]any{
				"collapse_key": collapse,
				"priority":     "high",
				"notification": map[string]string{"channel_id": "household"},
			},
			"apns": map[string]any{
				"headers": map[string]string{"apns-collapse-id": collapse, "apns-priority": "10"},
				"payload": map[string]any{"aps": map[string]any{"thread-id": m.HouseholdID, "sound": "default"}},
			},
		},
	}
}

// Send posts one message. Dead tokens come back as ErrUnregistered; everything
// else (quota, 5xx, network) is a plain error the caller logs and drops.
func (c *Client) Send(ctx context.Context, m Message) error {
	tok, err := c.tokens.Token(ctx)
	if err != nil {
		return err
	}
	body, _ := json.Marshal(payload(m))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	res, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("fcm: %w", err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<16))
	if res.StatusCode == http.StatusOK {
		return nil
	}
	var e struct {
		Error struct {
			Status  string `json:"status"`
			Message string `json:"message"`
			Details []struct {
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	_ = json.Unmarshal(raw, &e)
	code := e.Error.Status
	for _, d := range e.Error.Details {
		if d.ErrorCode != "" {
			code = d.ErrorCode
		}
	}
	switch {
	case res.StatusCode == http.StatusNotFound, code == "UNREGISTERED",
		res.StatusCode == http.StatusBadRequest && code == "INVALID_ARGUMENT",
		res.StatusCode == http.StatusForbidden && code == "SENDER_ID_MISMATCH":
		return fmt.Errorf("%w (HTTP %d %s)", ErrUnregistered, res.StatusCode, code)
	}
	return fmt.Errorf("fcm: HTTP %d %s", res.StatusCode, code)
}
