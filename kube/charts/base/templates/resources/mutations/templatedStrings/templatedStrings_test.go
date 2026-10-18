package templatedStrings

import (
	"reflect"
	"testing"
)

func TestTemplatedStrings_WrapsValidation(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"protocol": map[string]any{
				"type":        "string",
				"description": "the protocol",
				"enum":        []any{"HTTP", "HTTPS"},
			},
			"hostname": map[string]any{
				"type":      "string",
				"pattern":   "^[a-z]+$",
				"maxLength": 253,
			},
		},
	}

	got, err := (TemplatedStrings{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props := got.Schema["properties"].(map[string]any)

	protocol := props["protocol"].(map[string]any)
	want := map[string]any{
		"type":        "string",
		"description": "the protocol",
		"anyOf": []any{
			map[string]any{"enum": []any{"HTTP", "HTTPS"}},
			map[string]any{"pattern": TemplatePattern},
		},
	}
	if !reflect.DeepEqual(protocol, want) {
		t.Errorf("protocol = %#v, want %#v", protocol, want)
	}

	hostname := props["hostname"].(map[string]any)
	if _, ok := hostname["pattern"]; ok {
		t.Errorf("hostname keeps its pattern on the node: %#v", hostname)
	}
	anyOf := hostname["anyOf"].([]any)
	if !reflect.DeepEqual(anyOf[0], map[string]any{"pattern": "^[a-z]+$", "maxLength": 253}) {
		t.Errorf("hostname first branch = %#v, want its original validation", anyOf[0])
	}
}

func TestTemplatedStrings_KeepsNullableType(t *testing.T) {
	schema := map[string]any{
		"type":   []any{"string", "null"},
		"format": "date-time",
	}

	got, err := (TemplatedStrings{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !reflect.DeepEqual(got.Schema["type"], []any{"string", "null"}) {
		t.Errorf("type = %#v, want it untouched", got.Schema["type"])
	}
	if _, ok := got.Schema["anyOf"]; !ok {
		t.Errorf("expected anyOf, got %#v", got.Schema)
	}
}

func TestTemplatedStrings_LeavesOtherNodesUntouched(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"free":     map[string]any{"type": "string"},
			"number":   map[string]any{"type": "integer", "minimum": 1},
			"intOrStr": map[string]any{"x-kubernetes-int-or-string": true, "anyOf": []any{map[string]any{"type": "integer"}, map[string]any{"type": "string"}}},
			"combined": map[string]any{"type": "string", "pattern": "^a$", "oneOf": []any{map[string]any{"minLength": 1}}},
		},
	}
	want := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"free":     map[string]any{"type": "string"},
			"number":   map[string]any{"type": "integer", "minimum": 1},
			"intOrStr": map[string]any{"x-kubernetes-int-or-string": true, "anyOf": []any{map[string]any{"type": "integer"}, map[string]any{"type": "string"}}},
			"combined": map[string]any{"type": "string", "pattern": "^a$", "oneOf": []any{map[string]any{"minLength": 1}}},
		},
	}

	got, err := (TemplatedStrings{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !reflect.DeepEqual(got.Schema, want) {
		t.Errorf("schema = %#v, want %#v", got.Schema, want)
	}
}

func TestTemplatedStrings_WalksArraysAndMaps(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"hosts": map[string]any{
				"type":  "array",
				"items": map[string]any{"type": "string", "format": "hostname"},
			},
			"labels": map[string]any{
				"type":                 "object",
				"additionalProperties": map[string]any{"type": "string", "maxLength": 63},
			},
		},
	}

	got, err := (TemplatedStrings{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props := got.Schema["properties"].(map[string]any)
	items := props["hosts"].(map[string]any)["items"].(map[string]any)
	if _, ok := items["anyOf"]; !ok {
		t.Errorf("array items not wrapped: %#v", items)
	}
	values := props["labels"].(map[string]any)["additionalProperties"].(map[string]any)
	if _, ok := values["anyOf"]; !ok {
		t.Errorf("map values not wrapped: %#v", values)
	}
}
