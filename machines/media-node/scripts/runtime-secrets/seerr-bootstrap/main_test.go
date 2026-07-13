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

func TestJellyfinLibraryType(t *testing.T) {
	tests := map[string]string{
		"movies":  "movie",
		"tvshows": "show",
	}

	for collectionType, want := range tests {
		got, ok := jellyfinLibraryType(collectionType)
		if !ok {
			t.Fatalf("jellyfinLibraryType(%q) returned ok=false", collectionType)
		}
		if got != want {
			t.Fatalf("jellyfinLibraryType(%q) = %q, want %q", collectionType, got, want)
		}
	}
}

func TestJellyfinLibraryTypeRejectsUnsupportedFolders(t *testing.T) {
	if _, ok := jellyfinLibraryType("music"); ok {
		t.Fatal("jellyfinLibraryType(\"music\") returned ok=true, want false")
	}
}
