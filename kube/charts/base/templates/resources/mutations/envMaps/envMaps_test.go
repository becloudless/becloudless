package envMaps

import (
	"reflect"
	"testing"
)

func envSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"containers": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"env": map[string]any{
							"type": "array",
							"items": map[string]any{
								"type": "object",
								"properties": map[string]any{
									"name":      map[string]any{"type": "string"},
									"value":     map[string]any{"type": "string"},
									"valueFrom": map[string]any{"type": "object"},
								},
							},
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
}

func TestEnvMaps_ConvertsEnvArrayToValueOrValueFromMap(t *testing.T) {
	got, err := (EnvMaps{}).Mutate(envSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	containers := got.Schema["properties"].(map[string]any)["containers"].(map[string]any)
	items := containers["items"].(map[string]any)
	env := items["properties"].(map[string]any)["env"].(map[string]any)
	if env["type"] != "object" {
		t.Errorf("env.type = %v, want %q", env["type"], "object")
	}
	if _, ok := env["items"]; ok {
		t.Errorf("env.items should have been removed, got %#v", env["items"])
	}
	anyOf := env["additionalProperties"].(map[string]any)["anyOf"].([]any)
	if len(anyOf) != 2 {
		t.Fatalf("anyOf has %d entries, want 2", len(anyOf))
	}
	if !reflect.DeepEqual(anyOf[1], map[string]any{"type": "object"}) {
		t.Errorf("second anyOf entry should be the valueFrom schema, got %#v", anyOf[1])
	}

	// untouched: the containers array itself (left to ArraysToMaps) and the other arrays
	if containers["type"] != "array" {
		t.Errorf("containers.type = %v, want %q", containers["type"], "array")
	}
	args := items["properties"].(map[string]any)["args"].(map[string]any)
	if args["type"] != "array" {
		t.Errorf("args.type = %v, want %q", args["type"], "array")
	}

	if got.TemplateArgs["envPaths"] != `(list "containers.env")` {
		t.Errorf("envPaths = %s, want (list \"containers.env\")", got.TemplateArgs["envPaths"])
	}
}

func TestEnvMaps_IgnoresEnvArrayNotShapedLikeEnvVars(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"env": map[string]any{
				"type":  "array",
				"items": map[string]any{"type": "string"},
			},
		},
	}
	got, err := (EnvMaps{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	env := got.Schema["properties"].(map[string]any)["env"].(map[string]any)
	if env["type"] != "array" {
		t.Errorf("env.type = %v, want %q", env["type"], "array")
	}
	if got.TemplateArgs["envPaths"] != "(list )" {
		t.Errorf("envPaths = %s, want (list )", got.TemplateArgs["envPaths"])
	}
}
