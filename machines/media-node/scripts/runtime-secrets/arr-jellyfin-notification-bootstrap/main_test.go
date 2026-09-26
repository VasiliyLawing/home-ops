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

func TestApplyDesiredFieldsSetsScriptPath(t *testing.T) {
	schema := []field{{Name: "path"}, {Name: "arguments"}}

	got := applyDesiredFields(schema, "/nix/store/x/bin/notify")

	if value, _ := fieldValue(got, "path"); value != "/nix/store/x/bin/notify" {
		t.Fatalf("path = %v, want script path", value)
	}
	if value, _ := fieldValue(got, "arguments"); value != nil {
		t.Fatalf("arguments = %v, want untouched", value)
	}
}

func TestApplyDesiredFieldsIgnoresAbsentFields(t *testing.T) {
	// A field the running arr version does not expose must not be invented.
	got := applyDesiredFields([]field{{Name: "arguments"}}, "/nix/store/x/bin/notify")
	if _, ok := fieldValue(got, "path"); ok {
		t.Fatal("path should not be added when absent from schema")
	}
	if len(got) != 1 {
		t.Fatalf("expected field set to stay length 1, got %d", len(got))
	}
}
