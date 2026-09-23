package mutation

import "testing"

func TestArraysToMaps_ConvertsPlainArrayField(t *testing.T) {
	schema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"containers": map[string]interface{}{
				"type": "array",
				"items": map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"name": map[string]interface{}{"type": "string"},
					},
				},
			},
		},
	}
	e := &Entry{Name: "deployments"}

	got, err := ArraysToMaps(schema, e)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	containers := got["properties"].(map[string]interface{})["containers"].(map[string]interface{})
	if containers["type"] != "object" {
		t.Errorf("containers.type = %v, want %q", containers["type"], "object")
	}
	if _, ok := containers["additionalProperties"].(map[string]interface{}); !ok {
		t.Errorf("containers.additionalProperties is not a map: %#v", containers["additionalProperties"])
	}
	if _, ok := containers["items"]; ok {
		t.Errorf("containers.items should have been removed, got %#v", containers["items"])
	}
}

func TestArraysToMaps_IgnoresConfiguredPaths(t *testing.T) {
	// Mimics spec.containers[].command: an array of strings, which without
	// an ignore entry would (incorrectly) also be turned into a map.
	schema := map[string]interface{}{
		"type": "object",
		"properties": map[string]interface{}{
			"containers": map[string]interface{}{
				"type": "array",
				"items": map[string]interface{}{
					"type": "object",
					"properties": map[string]interface{}{
						"command": map[string]interface{}{
							"type":  "array",
							"items": map[string]interface{}{"type": "string"},
						},
						"args": map[string]interface{}{
							"type":  "array",
							"items": map[string]interface{}{"type": "string"},
						},
					},
				},
			},
		},
	}
	e := &Entry{
		Name: "deployments",
		MutationConfig: map[string]map[string][]string{
			"arraysToMaps": {
				"ignore": {"containers.command"},
			},
		},
	}

	got, err := ArraysToMaps(schema, e)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	containerItems := got["properties"].(map[string]interface{})["containers"].(map[string]interface{})["additionalProperties"].(map[string]interface{})
	props := containerItems["properties"].(map[string]interface{})

	command := props["command"].(map[string]interface{})
	if command["type"] != "array" {
		t.Errorf("command.type = %v, want unchanged %q (ignored path)", command["type"], "array")
	}
	if _, ok := command["items"]; !ok {
		t.Errorf("command.items should have been preserved, got %#v", command)
	}

	// "args" wasn't listed in the ignore config, so it should still be
	// converted like any other array field.
	args := props["args"].(map[string]interface{})
	if args["type"] != "object" {
		t.Errorf("args.type = %v, want %q (not ignored, should still convert)", args["type"], "object")
	}
}

func TestArraysToMaps_NilEntryDoesNotPanic(t *testing.T) {
	schema := map[string]interface{}{
		"type": "array",
		"items": map[string]interface{}{
			"type": "string",
		},
	}

	got, err := ArraysToMaps(schema, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got["type"] != "object" {
		t.Errorf("type = %v, want %q", got["type"], "object")
	}
}
