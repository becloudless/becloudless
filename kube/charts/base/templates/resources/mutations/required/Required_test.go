package required

import (
	"reflect"
	"testing"
)

func TestRequired_RootRequired(t *testing.T) {
	schema := map[string]any{
		"type":     "object",
		"required": []any{"minReplicas", "maxReplicas"},
		"properties": map[string]any{
			"minReplicas": map[string]any{"type": "integer"},
			"maxReplicas": map[string]any{"type": "integer"},
		},
	}
	got, err := (Required{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := got.Schema["required"]; ok {
		t.Errorf("root required should have been removed from the schema, got %#v", got.Schema["required"])
	}
	want := `(dict "required" (list "maxReplicas" "minReplicas"))`
	if got.TemplateArgs["required"] != want {
		t.Errorf("required = %s, want %s", got.TemplateArgs["required"], want)
	}
}

func TestRequired_NestedPropertiesAndEntries(t *testing.T) {
	// Mimics deployments: spec.containers is a map keyed by id (ArraysToMaps ran before).
	schema := map[string]any{
		"type":     "object",
		"required": []any{"template"},
		"properties": map[string]any{
			"template": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"spec": map[string]any{
						"type":     "object",
						"required": []any{"containers"},
						"properties": map[string]any{
							"containers": map[string]any{
								"type": "object",
								"additionalProperties": map[string]any{
									"type":     "object",
									"required": []any{"name", "image"},
									"properties": map[string]any{
										"name":  map[string]any{"type": "string"},
										"image": map[string]any{"type": "string"},
									},
								},
							},
							"hostname": map[string]any{"type": "string"},
						},
					},
				},
			},
		},
	}
	got, err := (Required{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	want := `(dict "required" (list "template") "properties" (dict "template" (dict "properties" (dict "spec" (dict "required" (list "containers") "properties" (dict "containers" (dict "each" (dict "required" (list "image" "name")))))))))`
	if got.TemplateArgs["required"] != want {
		t.Errorf("required =\n%s\nwant\n%s", got.TemplateArgs["required"], want)
	}

	spec := got.Schema["properties"].(map[string]any)["template"].(map[string]any)["properties"].(map[string]any)["spec"].(map[string]any)
	if _, ok := spec["required"]; ok {
		t.Errorf("spec.required should have been removed from the schema, got %#v", spec["required"])
	}
	container := spec["properties"].(map[string]any)["containers"].(map[string]any)["additionalProperties"].(map[string]any)
	if _, ok := container["required"]; ok {
		t.Errorf("container.required should have been removed from the schema, got %#v", container["required"])
	}
}

func TestRequired_ItemsOfAList(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"dependsOn": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type":     "object",
					"required": []any{"name"},
				},
			},
		},
	}
	got, err := (Required{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := `(dict "properties" (dict "dependsOn" (dict "each" (dict "required" (list "name")))))`
	if got.TemplateArgs["required"] != want {
		t.Errorf("required =\n%s\nwant\n%s", got.TemplateArgs["required"], want)
	}
}

func TestRequired_AlternativeBranchesKeepTheirOwnRequired(t *testing.T) {
	// Mimics a kyverno context entry (exactly one of the fields) and an env value (a scalar or a valueFrom object).
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"context": map[string]any{
				"type": "object",
				"oneOf": []any{
					map[string]any{"required": []any{"configMap"}},
					map[string]any{"required": []any{"variable"}},
				},
			},
			"env": map[string]any{
				"type": "object",
				"additionalProperties": map[string]any{
					"anyOf": []any{
						map[string]any{"type": "string"},
						map[string]any{
							"type": "object",
							"properties": map[string]any{
								"secretKeyRef": map[string]any{
									"type":     "object",
									"required": []any{"key"},
								},
							},
						},
					},
				},
			},
		},
	}
	got, err := (Required{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	want := `(dict "properties" (dict "env" (dict "each" (dict "properties" (dict "secretKeyRef" (dict "required" (list "key")))))))`
	if got.TemplateArgs["required"] != want {
		t.Errorf("required =\n%s\nwant\n%s", got.TemplateArgs["required"], want)
	}

	oneOf := got.Schema["properties"].(map[string]any)["context"].(map[string]any)["oneOf"].([]any)
	wantOneOf := []any{
		map[string]any{"required": []any{"configMap"}},
		map[string]any{"required": []any{"variable"}},
	}
	if !reflect.DeepEqual(oneOf, wantOneOf) {
		t.Errorf("oneOf = %#v, want the alternatives untouched %#v", oneOf, wantOneOf)
	}
}

func TestRequired_AllOfBranchesAreRequiredToo(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"allOf": []any{
			map[string]any{"required": []any{"a"}},
			map[string]any{"required": []any{"b"}},
		},
	}
	got, err := (Required{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := `(dict "required" (list "a" "b"))`
	if got.TemplateArgs["required"] != want {
		t.Errorf("required = %s, want %s", got.TemplateArgs["required"], want)
	}
}

func TestRequired_NothingRequired(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"data": map[string]any{
				"type":                 "object",
				"additionalProperties": map[string]any{"type": "string"},
			},
		},
	}
	got, err := (Required{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got.TemplateArgs) != 0 {
		t.Errorf("TemplateArgs = %#v, want none", got.TemplateArgs)
	}
}
