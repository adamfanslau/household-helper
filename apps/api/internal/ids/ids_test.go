package ids

import (
	"strings"
	"testing"
)

func TestInviteCodes(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 200; i++ {
		c := NewInviteCode()
		if len(c) != InviteCodeLen || !ValidInviteCode(c) || strings.ContainsAny(c, "IO01") {
			t.Fatalf("bad generated code %q", c)
		}
		seen[c] = true
	}
	if len(seen) < 199 {
		t.Fatal("codes are not random enough")
	}
	for _, ok := range []string{"MOCK1234", "JOIN5678", "ABCDEF01", "BOGUS123"} {
		if !ValidInviteCode(ok) {
			t.Fatalf("%q should be a valid shape", ok)
		}
	}
	for _, bad := range []string{"", "SHORT", "mock1234", "ABCDEFGH1", "ABCD-EFG", "ÄBCDEFGH"} {
		if ValidInviteCode(bad) {
			t.Fatalf("%q should be rejected", bad)
		}
	}
	if len(New()) != 36 {
		t.Fatal("uuid shape")
	}
}
