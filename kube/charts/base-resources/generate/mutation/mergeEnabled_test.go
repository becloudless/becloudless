package mutation

import (
	"reflect"
	"testing"
)

func TestMergeEnabled_AddsEnabledProperty(t *testing.T) {
	schema := map[string]any{}
	e := &Entry{Name: "widgets"}

	got, err := (MergeEnabled{}).Mutate(schema, e)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if got["type"] != "object" {
		t.Errorf("type = %v, want %q", got["type"], "object")
	}

	props, ok := got["properties"].(map[string]any)
	if !ok {
		t.Fatalf("properties is not a map: %#v", got["properties"])
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
	e := &Entry{Name: "configMaps"}

	got, err := (MergeEnabled{}).Mutate(schema, e)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props := got["properties"].(map[string]any)
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
	e := &Entry{Name: "widgets"}

	got, err := (MergeEnabled{}).Mutate(schema, e)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props := got["properties"].(map[string]any)
	enabled := props["enabled"].(map[string]any)
	if enabled["type"] != "boolean" {
		t.Errorf("properties.enabled.type = %v, want %q (should override upstream field)", enabled["type"], "boolean")
	}
}

func TestMergeEnabled_DoesNotMutateEntry(t *testing.T) {
	schema := map[string]any{}
	e := &Entry{Name: "widgets", TemplateArgs: []TemplateArg{{Name: "required", Value: `(list "foo")`}}}

	if _, err := (MergeEnabled{}).Mutate(schema, e); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	want := []TemplateArg{{Name: "required", Value: `(list "foo")`}}
	if !reflect.DeepEqual(e.TemplateArgs, want) {
		t.Errorf("e.TemplateArgs = %v, want unchanged %v", e.TemplateArgs, want)
	}
}
