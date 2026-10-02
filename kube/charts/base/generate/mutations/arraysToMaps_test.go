package mutations

import "testing"

func TestArraysToMaps_ConvertsPlainArrayField(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"containers": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"name": map[string]any{"type": "string"},
					},
				},
			},
		},
	}
	got, err := (ArraysToMaps{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	containers := got.Schema["properties"].(map[string]any)["containers"].(map[string]any)
	if containers["type"] != "object" {
		t.Errorf("containers.type = %v, want %q", containers["type"], "object")
	}
	if _, ok := containers["additionalProperties"].(map[string]any); !ok {
		t.Errorf("containers.additionalProperties is not a map: %#v", containers["additionalProperties"])
	}
	if _, ok := containers["items"]; ok {
		t.Errorf("containers.items should have been removed, got %#v", containers["items"])
	}
}

func TestArraysToMaps_IgnoresConfiguredPaths(t *testing.T) {
	// Mimics spec.containers[].command: an array of strings, which without
	// an ignore entry would (incorrectly) also be turned into a map.
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"containers": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"command": map[string]any{
							"type":  "array",
							"items": map[string]any{"type": "string"},
						},
						"args": map[string]any{
							"type":  "array",
							"items": map[string]any{"type": "string"},
						},
					},
				},
			},
		},
	}
	m := ArraysToMaps{Ignore: []string{"containers.command"}}

	got, err := m.Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	containerItems := got.Schema["properties"].(map[string]any)["containers"].(map[string]any)["additionalProperties"].(map[string]any)
	props := containerItems["properties"].(map[string]any)

	command := props["command"].(map[string]any)
	if command["type"] != "array" {
		t.Errorf("command.type = %v, want unchanged %q (ignored path)", command["type"], "array")
	}
	if _, ok := command["items"]; !ok {
		t.Errorf("command.items should have been preserved, got %#v", command)
	}

	// "args" wasn't listed in the ignore config, so it should still be
	// converted like any other array field.
	args := props["args"].(map[string]any)
	if args["type"] != "object" {
		t.Errorf("args.type = %v, want %q (not ignored, should still convert)", args["type"], "object")
	}
}

func TestArraysToMaps_EmptySchemaDoesNotPanic(t *testing.T) {
	schema := map[string]any{
		"type": "array",
		"items": map[string]any{
			"type": "string",
		},
	}

	got, err := (ArraysToMaps{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Schema["type"] != "object" {
		t.Errorf("type = %v, want %q", got.Schema["type"], "object")
	}
}
