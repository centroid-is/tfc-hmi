package update

import (
	"fmt"
	"testing"
)

func TestParseVersion(t *testing.T) {
	cases := []struct {
		input   string
		wantErr bool
	}{
		{"2026.3.6", false},
		{"v2026.3.6", false},         // v prefix stripped
		{"2026.3.6+1", false},        // build metadata stripped
		{"", true},                   // empty string returns error
		{"not-a-version", true},      // invalid version returns error
	}
	for _, tc := range cases {
		t.Run(tc.input, func(t *testing.T) {
			_, err := ParseVersion(tc.input)
			if tc.wantErr && err == nil {
				t.Errorf("ParseVersion(%q) expected error, got nil", tc.input)
			}
			if !tc.wantErr && err != nil {
				t.Errorf("ParseVersion(%q) unexpected error: %v", tc.input, err)
			}
		})
	}
}

func TestIsNewer(t *testing.T) {
	cases := []struct {
		candidate string
		current   string
		want      bool
	}{
		{"2026.10.1", "2026.9.30", true},   // CRITICAL: double-digit month boundary
		{"2026.3.6", "2026.3.5", true},
		{"2026.3.6", "2026.3.6", false},
		{"2026.3.5", "2026.3.6", false},
		{"2026.3.6+1", "2026.3.5+99", true}, // build metadata ignored
		{"v2026.3.6", "2026.3.5", true},      // v prefix stripped
	}
	for _, tc := range cases {
		t.Run(fmt.Sprintf("%s_vs_%s", tc.candidate, tc.current), func(t *testing.T) {
			got, err := IsNewer(tc.candidate, tc.current)
			if err != nil {
				t.Fatal(err)
			}
			if got != tc.want {
				t.Errorf("IsNewer(%q, %q) = %v, want %v", tc.candidate, tc.current, got, tc.want)
			}
		})
	}
}
