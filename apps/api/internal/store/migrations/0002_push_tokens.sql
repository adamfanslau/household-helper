-- FCM registration tokens (api step E). One row per device token; a token moves to
-- whoever registers it last. Pruned daily when not seen for 60 days.

CREATE TABLE push_tokens (
  token        TEXT PRIMARY KEY CHECK (length(token) BETWEEN 1 AND 4096),
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform     TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  created_at   TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);
CREATE INDEX push_tokens_user_id_idx ON push_tokens(user_id);
