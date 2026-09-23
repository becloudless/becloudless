package mutation

import "testing"

func TestMergeEnabled_AddsEnabledProperty(t *testing.T) {
	schema := map[string]any{}

	got, err := (MergeEnabled{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if got.Schema["type"] != "object" {
		t.Errorf("type = %v, want %q", got.Schema["type"], "object")
	}

	props, ok := got.Schema["properties"].(map[string]any)
	if !ok {
		t.Fatalf("properties is not a map: %#v", got.Schema["properties"])
	}

	enabled, ok := props["enabled"].(map[string]any)
	if !ok {
		t.Fatalf("properties.enabled is not a map: %#v", props["enabled"])
	}
	if enabled["type"] != "boolean" {
		t.Errorf("properties.enabled.type = %v, want %q", enabled["type"], "boolean")
	}
	if desc, ok := enabled["description"].(string); !ok || desc == "" {
		t.Errorf("properties.enabled.description should be a non-empty string, got %#v", enabled["description"])
	}
}

func TestMergeEnabled_PreservesExistingProperties(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"data": map[string]any{"type": "object"},
		},
	}

	got, err := (MergeEnabled{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props := got.Schema["properties"].(map[string]any)
	if _, ok := props["data"]; !ok {
		t.Errorf("expected existing property %q to be preserved, got %#v", "data", props)
	}
	if _, ok := props["enabled"]; !ok {
		t.Errorf("expected %q property to be added, got %#v", "enabled", props)
	}
}

func TestMergeEnabled_OverridesUpstreamEnabledProperty(t *testing.T) {
	// Guards against an upstream CRD ever shadowing the well-known "enabled"
	// field with an incompatible schema, mirroring MergeMetadata's
	// precedence over same-named upstream fields.
	schema := map[string]any{
		"properties": map[string]any{
			"enabled": map[string]any{"type": "string"},
		},
	}

	got, err := (MergeEnabled{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props := got.Schema["properties"].(map[string]any)
	enabled := props["enabled"].(map[string]any)
	if enabled["type"] != "boolean" {
		t.Errorf("properties.enabled.type = %v, want %q (should override upstream field)", enabled["type"], "boolean")
	}
}

func TestMergeEnabled_ReturnsNoTemplateArgs(t *testing.T) {
	schema := map[string]any{}

	got, err := (MergeEnabled{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(got.TemplateArgs) != 0 {
		t.Errorf("TemplateArgs = %#v, want none", got.TemplateArgs)
	}
}
