package ui

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/centroid-is/centroidx-manager/internal/update"
)

func buildTestReleases() []update.ReleaseInfo {
	return []update.ReleaseInfo{
		{
			Version:     "2026.10.1",
			Notes:       "## Release Notes\n- Feature A\n- Bug fix B",
			PublishedAt: time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC),
		},
		{
			Version:     "2026.3.6",
			Notes:       "## Release 2026.3.6\n- Improvement C",
			PublishedAt: time.Date(2026, 3, 6, 0, 0, 0, 0, time.UTC),
		},
		{
			Version:     "2026.3.5",
			Notes:       "## Release 2026.3.5\n- Fix D",
			PublishedAt: time.Date(2026, 3, 5, 0, 0, 0, 0, time.UTC),
		},
	}
}

func TestPickerState_InitialState(t *testing.T) {
	state := &pickerState{
		loading:  true,
		selected: -1,
	}
	if !state.loading {
		t.Error("expected loading=true initially")
	}
	if state.selected != -1 {
		t.Errorf("expected selected=-1, got %d", state.selected)
	}
}

func TestPickerState_ReleasesLoaded(t *testing.T) {
	state := &pickerState{
		releases: buildTestReleases(),
		selected: -1,
	}
	if len(state.releases) != 3 {
		t.Errorf("expected 3 releases, got %d", len(state.releases))
	}
}

func TestPickerState_Selection(t *testing.T) {
	state := &pickerState{
		releases: buildTestReleases(),
		selected: 0,
	}
	if state.releases[state.selected].Version != "2026.10.1" {
		t.Errorf("expected version 2026.10.1, got %s", state.releases[state.selected].Version)
	}
}

func TestUserFriendlyMessage_Network(t *testing.T) {
	tests := []struct {
		input    string
		contains string
	}{
		{"connection refused", "Network Error"},
		{"dial tcp: no such host", "Network Error"},
		{"checksum mismatch", "Download Verification"},
		{"access denied", "Permission Error"},
		{"something random", "something random"},
	}
	for _, tt := range tests {
		msg := userFriendlyMessage(fmt.Errorf("%s", tt.input))
		if !strings.Contains(msg, tt.contains) {
			t.Errorf("userFriendlyMessage(%q) = %q, want to contain %q", tt.input, msg, tt.contains)
		}
	}
}
