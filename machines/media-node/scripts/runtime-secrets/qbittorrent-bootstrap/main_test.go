package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestSetINIValueAddsSection(t *testing.T) {
	got := setINIValue(nil, "Preferences", `WebUI\Port`, "8081")
	want := []string{"[Preferences]", `WebUI\Port=8081`}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("setINIValue() = %#v, want %#v", got, want)
	}
}

func TestSetINIValueUpdatesExistingKey(t *testing.T) {
	got := setINIValue([]string{
		"[Preferences]",
		`WebUI\Port=8080`,
		`Connection\UPnP=true`,
	}, "Preferences", `Connection\UPnP`, "false")

	want := []string{
		"[Preferences]",
		`WebUI\Port=8080`,
		`Connection\UPnP=false`,
	}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("setINIValue() = %#v, want %#v", got, want)
	}
}

func TestReadConfigLinesNormalizesWindowsNewlines(t *testing.T) {
	path := filepath.Join(t.TempDir(), "qBittorrent.conf")
	if err := os.WriteFile(path, []byte("[Preferences]\r\nWebUI\\Port=8081\r\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	got, err := readConfigLines(path)
	if err != nil {
		t.Fatal(err)
	}

	want := []string{"[Preferences]", `WebUI\Port=8081`}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("readConfigLines() = %#v, want %#v", got, want)
	}
}
