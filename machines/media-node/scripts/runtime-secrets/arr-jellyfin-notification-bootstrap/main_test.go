package main

import "testing"

func fieldValue(fields []field, name string) (interface{}, bool) {
	for _, item := range fields {
		if item.Name == name {
			return item.Value, true
		}
	}
	return nil, false
}

func TestApplyDesiredFieldsSetsUpdateLibrary(t *testing.T) {
	schema := []field{
		{Name: "host"},
		{Name: "port"},
		{Name: "useSsl"},
		{Name: "urlBase"},
		{Name: "apiKey"},
		{Name: "notify"},
		{Name: "updateLibrary"},
	}

	got := applyDesiredFields(schema, "127.0.0.1", 8096, "secret-key")

	want := map[string]interface{}{
		"host":          "127.0.0.1",
		"port":          8096,
		"useSsl":        false,
		"urlBase":       "",
		"apiKey":        "secret-key",
		"notify":        false,
		"updateLibrary": true,
	}
	for name, expected := range want {
		value, ok := fieldValue(got, name)
		if !ok {
			t.Fatalf("field %q missing after applyDesiredFields", name)
		}
		if value != expected {
			t.Fatalf("field %q = %v, want %v", name, value, expected)
		}
	}
}

func TestApplyDesiredFieldsIgnoresAbsentFields(t *testing.T) {
	// A field the running arr version does not expose must not be invented.
	got := applyDesiredFields([]field{{Name: "host"}}, "127.0.0.1", 8096, "key")
	if _, ok := fieldValue(got, "updateLibrary"); ok {
		t.Fatal("updateLibrary should not be added when absent from schema")
	}
	if len(got) != 1 {
		t.Fatalf("expected field set to stay length 1, got %d", len(got))
	}
}
