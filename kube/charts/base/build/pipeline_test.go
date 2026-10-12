package build

import (
	"testing"

	"resourceschart/templates/resources/mutations"
	"resourceschart/templates/resources/mutations/content"
)

func TestPipeline_EnabledSurvivesFullPipeline(t *testing.T) {
	// Mimics a CRD-style schema (content wrapped in "spec", the default),
	// similar to the upstream k8s JSON schema fed into Apply by
	// fetchSchemas.
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"apiVersion": map[string]any{"type": "string"},
			"kind":       map[string]any{"type": "string"},
			"metadata":   map[string]any{"type": "object"},
			"spec": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"replicas": map[string]any{"type": "integer"},
				},
			},
		},
	}
	got, err := mutations.MutateSchema(Pipeline(content.ExtractContent{}, nil, nil), schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props, ok := got.Schema["properties"].(map[string]any)
	if !ok {
		t.Fatalf("properties is not a map: %#v", got.Schema["properties"])
	}

	enabled, ok := props["enabled"].(map[string]any)
	if !ok {
		t.Fatalf("expected \"enabled\" property in final schema, got %#v", props)
	}
	if enabled["type"] != "boolean" {
		t.Errorf("enabled.type = %v, want %q", enabled["type"], "boolean")
	}

	// AdditionalPropertiesFalse runs after MergeEnabled, so the top-level
	// object (which now includes "enabled" among its declared properties)
	// must still end up closed against unknown properties.
	if got.Schema["additionalProperties"] != false {
		t.Errorf("top-level additionalProperties = %v, want false", got.Schema["additionalProperties"])
	}
}
