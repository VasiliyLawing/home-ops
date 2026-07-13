package main

import (
	"reflect"
	"testing"
)

func TestUpsertAddsMissingSection(t *testing.T) {
	got := upsert([]string{"general:", "  use_sonarr: false"}, "sonarr", "port", 8989)
	want := []string{"general:", "  use_sonarr: false", "", "sonarr:", "  port: 8989"}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("upsert() = %#v, want %#v", got, want)
	}
}

func TestUpsertUpdatesExistingKey(t *testing.T) {
	got := upsert([]string{
		"sonarr:",
		"  ip: \"localhost\"",
		"  port: 1234",
		"radarr:",
		"  port: 7878",
	}, "sonarr", "port", 8989)

	want := []string{
		"sonarr:",
		"  ip: \"localhost\"",
		"  port: 8989",
		"radarr:",
		"  port: 7878",
	}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("upsert() = %#v, want %#v", got, want)
	}
}

func TestUpsertInsertsBeforeNextTopLevelSection(t *testing.T) {
	got := upsert([]string{
		"sonarr:",
		"  ip: \"127.0.0.1\"",
		"radarr:",
		"  port: 7878",
	}, "sonarr", "apikey", "secret")

	want := []string{
		"sonarr:",
		"  ip: \"127.0.0.1\"",
		"  apikey: \"secret\"",
		"radarr:",
		"  port: 7878",
	}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("upsert() = %#v, want %#v", got, want)
	}
}
