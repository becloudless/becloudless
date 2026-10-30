package arraysToMaps

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

func TestArraysToMaps_DisabledKeepsEveryArray(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"rules": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"kinds": map[string]any{
							"type":  "array",
							"items": map[string]any{"type": "string"},
						},
					},
				},
			},
		},
	}

	got, err := (ArraysToMaps{Disabled: true}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	rules := got.Schema["properties"].(map[string]any)["rules"].(map[string]any)
	if rules["type"] != "array" {
		t.Errorf("rules.type = %v, want unchanged %q", rules["type"], "array")
	}
	items := rules["items"].(map[string]any)
	kinds := items["properties"].(map[string]any)["kinds"].(map[string]any)
	if kinds["type"] != "array" {
		t.Errorf("kinds.type = %v, want unchanged %q", kinds["type"], "array")
	}
	if got.TemplateArgs["arrayPaths"] != "(list )" {
		t.Errorf("arrayPaths = %q, want an empty list", got.TemplateArgs["arrayPaths"])
	}
}

func keyFieldsSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"fields": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"fieldName": map[string]any{"type": "string"},
					},
				},
			},
		},
	}
}

func TestArraysToMaps_KeyFieldsReportedAsTemplateArg(t *testing.T) {
	got, err := (ArraysToMaps{KeyFields: map[string]string{"fields": "fieldName"}}).Mutate(keyFieldsSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if want := `(dict "fields" "fieldName")`; got.TemplateArgs["keyFields"] != want {
		t.Errorf("keyFields = %q, want %q", got.TemplateArgs["keyFields"], want)
	}
}

func TestArraysToMaps_NoKeyFieldsReportsNoTemplateArg(t *testing.T) {
	got, err := (ArraysToMaps{}).Mutate(keyFieldsSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := got.TemplateArgs["keyFields"]; ok {
		t.Errorf("keyFields should not be reported, got %q", got.TemplateArgs["keyFields"])
	}
}

func TestArraysToMaps_KeyFieldsRejectsUnknownPathOrProperty(t *testing.T) {
	for name, keyFields := range map[string]map[string]string{
		"unknown path":     {"nope": "fieldName"},
		"unknown property": {"fields": "nope"},
	} {
		if _, err := (ArraysToMaps{KeyFields: keyFields}).Mutate(keyFieldsSchema()); err == nil {
			t.Errorf("%s: expected an error, got none", name)
		}
	}
}
