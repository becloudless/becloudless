package main

import "testing"

func TestDefaultTransformers_EnabledSurvivesFullPipeline(t *testing.T) {
	// Mimics a CRD-style schema (contentIsSpec: true), similar to the
	// upstream k8s JSON schema fed into applyTransformers by fetchSchemas.
	schema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"apiVersion": map[string]interface{}{"type": "string"},
			"kind":       map[string]interface{}{"type": "string"},
			"metadata":   map[string]interface{}{"type": "object"},
			"spec": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"replicas": map[string]interface{}{"type": "integer"},
				},
			},
		},
	}
	e := &entry{name: "widgets", contentIsSpec: true}

	got, err := applyTransformers(defaultTransformers, schema, e)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props, ok := got["properties"].(map[string]interface{})
	if !ok {
		t.Fatalf("properties is not a map: %#v", got["properties"])
	}

	enabled, ok := props["enabled"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected \"enabled\" property in final schema, got %#v", props)
	}
	if enabled["type"] != "boolean" {
		t.Errorf("enabled.type = %v, want %q", enabled["type"], "boolean")
	}

	// additionalPropertiesFalseTransform runs after mergeEnabledTransform, so
	// the top-level object (which now includes "enabled" among its declared
	// properties) must still end up closed against unknown properties.
	if got["additionalProperties"] != false {
		t.Errorf("top-level additionalProperties = %v, want false", got["additionalProperties"])
	}
}
