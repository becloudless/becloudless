package yamlNodes

import (
	"reflect"
	"strings"
	"testing"
)

func patchSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"postRenderers": map[string]any{
				"type": "object",
				"additionalProperties": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"kustomize": map[string]any{
							"type": "object",
							"properties": map[string]any{
								"patches": map[string]any{
									"type": "object",
									"additionalProperties": map[string]any{
										"type": "object",
										"properties": map[string]any{
											"patch":  map[string]any{"type": "string", "description": "the patch", "minLength": 1, "format": "yaml"},
											"target": map[string]any{"type": "string"},
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}
}

func patchNode(schema map[string]any) map[string]any {
	node := schema["properties"].(map[string]any)["postRenderers"].(map[string]any)["additionalProperties"].(map[string]any)
	node = node["properties"].(map[string]any)["kustomize"].(map[string]any)["properties"].(map[string]any)["patches"].(map[string]any)
	return node["additionalProperties"].(map[string]any)["properties"].(map[string]any)["patch"].(map[string]any)
}

func TestYamlNodes_AcceptsAStringAnObjectAndAnArray(t *testing.T) {
	m := YamlNodes{Fields: []string{"postRenderers.kustomize.patches.patch"}}

	got, err := m.Mutate(patchSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	patch := patchNode(got.Schema)
	if want := []any{"string", "object", "array"}; !reflect.DeepEqual(patch["type"], want) {
		t.Errorf("patch.type = %v, want %v", patch["type"], want)
	}
	for _, key := range []string{"minLength", "format"} {
		if _, ok := patch[key]; ok {
			t.Errorf("patch.%s should be dropped, got %v", key, patch[key])
		}
	}
	if patch["description"] != "the patch" {
		t.Errorf("patch.description = %v, want it kept", patch["description"])
	}
}

func TestYamlNodes_OnlyTheDeclaredField(t *testing.T) {
	m := YamlNodes{Fields: []string{"postRenderers.kustomize.patches.patch"}}

	got, err := m.Mutate(patchSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	node := got.Schema["properties"].(map[string]any)["postRenderers"].(map[string]any)["additionalProperties"].(map[string]any)
	node = node["properties"].(map[string]any)["kustomize"].(map[string]any)["properties"].(map[string]any)["patches"].(map[string]any)
	target := node["additionalProperties"].(map[string]any)["properties"].(map[string]any)["target"].(map[string]any)
	if target["type"] != "string" {
		t.Errorf("target.type = %v, want it untouched", target["type"])
	}
}

func TestYamlNodes_ReportsThePathsAsTemplateArg(t *testing.T) {
	m := YamlNodes{Fields: []string{"postRenderers.kustomize.patches.patch"}}

	got, err := m.Mutate(patchSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := `(list "postRenderers.kustomize.patches.patch")`
	if got.TemplateArgs["yamlNodes"] != want {
		t.Errorf("yamlNodes = %q, want %q", got.TemplateArgs["yamlNodes"], want)
	}
}

func TestYamlNodes_NothingConfiguredReportsNothing(t *testing.T) {
	got, err := (YamlNodes{}).Mutate(patchSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := got.TemplateArgs["yamlNodes"]; ok {
		t.Errorf("yamlNodes should not be reported, got %q", got.TemplateArgs["yamlNodes"])
	}
	if patchNode(got.Schema)["type"] != "string" {
		t.Errorf("the schema should be untouched")
	}
}

func TestYamlNodes_RejectsAPathThatIsNotAStringField(t *testing.T) {
	for _, path := range []string{"postRenderers.kustomize.patches", "postRenderers.kustomize.nothing", "patch"} {
		_, err := (YamlNodes{Fields: []string{path}}).Mutate(patchSchema())
		if err == nil || !strings.Contains(err.Error(), path) {
			t.Errorf("path %q: expected an error naming it, got %v", path, err)
		}
	}
}
