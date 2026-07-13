package main

import "testing"

func TestArrDisplayName(t *testing.T) {
	tests := map[string]string{
		"sonarr": "Sonarr",
		"radarr": "Radarr",
	}

	for kind, want := range tests {
		got, err := arrDisplayName(kind)
		if err != nil {
			t.Fatalf("arrDisplayName(%q) returned error: %v", kind, err)
		}
		if got != want {
			t.Fatalf("arrDisplayName(%q) = %q, want %q", kind, got, want)
		}
	}
}

func TestArrDisplayNameRejectsUnknownKind(t *testing.T) {
	if _, err := arrDisplayName("lidarr"); err == nil {
		t.Fatal("arrDisplayName(\"lidarr\") returned nil error, want non-nil")
	}
}
