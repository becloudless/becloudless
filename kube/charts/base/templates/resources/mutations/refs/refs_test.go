package refs

import "testing"

// the schema of a route: `parentRefs` and `rules.backendRefs` are maps keyed by id (converted from arrays by ArraysToMaps)
func routeSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"parentRefs": map[string]any{
				"type": "object",
				"additionalProperties": map[string]any{
					"type":       "object",
					"properties": map[string]any{"name": map[string]any{"type": "string"}},
				},
			},
			"endpointSelector": map[string]any{
				"type":       "object",
				"properties": map[string]any{"matchLabels": map[string]any{"type": "object"}},
			},
			"rules": map[string]any{
				"type": "object",
				"additionalProperties": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"backendRefs": map[string]any{
							"type": "object",
							"additionalProperties": map[string]any{
								"type": "object",
								"properties": map[string]any{
									"name": map[string]any{"type": "string", "maxLength": 253},
								},
							},
						},
					},
				},
			},
		},
	}
}

func property(node map[string]any, name string) map[string]any {
	return node["properties"].(map[string]any)[name].(map[string]any)
}

func TestRefs_AStringPositionAcceptsAReferenceOrItsOriginalSchema(t *testing.T) {
	m := Refs{"rules.backendRefs.name": {Kinds: []string{"services"}, As: "name"}}

	got, err := m.Mutate(routeSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	rules := property(got.Schema, "rules")["additionalProperties"].(map[string]any)
	backends := property(rules, "backendRefs")["additionalProperties"].(map[string]any)
	name := property(backends, "name")
	branches, _ := name["anyOf"].([]any)
	if len(branches) != 2 {
		t.Fatalf("name = %#v, want an anyOf of the reference and the original", name)
	}
	if branches[0].(map[string]any)["pattern"] != Pattern {
		t.Errorf("first branch = %#v, want the pattern of a reference", branches[0])
	}
	if branches[1].(map[string]any)["maxLength"] != 253 {
		t.Errorf("second branch = %#v, want the original schema", branches[1])
	}
	want := `(dict "rules.backendRefs.name" (dict "kinds" (list "services") "as" "name"))`
	if got.TemplateArgs["refs"] != want {
		t.Errorf("refs = %q, want %q", got.TemplateArgs["refs"], want)
	}
}

func TestRefs_AMapOfObjectsAcceptsReferencesAsEntriesAndAsAList(t *testing.T) {
	m := Refs{"parentRefs": {Kinds: []string{"listenerSets", "gateways"}, As: "gatewayRef"}}

	got, err := m.Mutate(routeSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	node := property(got.Schema, "parentRefs")
	types, _ := node["type"].([]any)
	if len(types) != 2 || types[0] != "object" || types[1] != "array" {
		t.Errorf("type = %#v, want object and array", node["type"])
	}
	items, _ := node["items"].(map[string]any)
	if items["pattern"] != Pattern {
		t.Errorf("items = %#v, want the pattern of a reference", node["items"])
	}
	entry, _ := node["additionalProperties"].(map[string]any)
	branches, _ := entry["anyOf"].([]any)
	if len(branches) != 2 || branches[0].(map[string]any)["pattern"] != Pattern {
		t.Fatalf("additionalProperties = %#v, want an anyOf of the reference and the entry", entry)
	}
	if branches[1].(map[string]any)["type"] != "object" {
		t.Errorf("the entry should be kept, got %#v", branches[1])
	}
	want := `(dict "parentRefs" (dict "kinds" (list "listenerSets" "gateways") "as" "gatewayRef"))`
	if got.TemplateArgs["refs"] != want {
		t.Errorf("refs = %q, want %q", got.TemplateArgs["refs"], want)
	}
}

func TestRefs_ASingleObjectAcceptsAReferenceOrItself(t *testing.T) {
	m := Refs{"endpointSelector": {Kinds: []string{"deployments"}, As: "podSelector"}}

	got, err := m.Mutate(routeSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	node := property(got.Schema, "endpointSelector")
	branches, _ := node["anyOf"].([]any)
	if len(branches) != 2 || branches[0].(map[string]any)["pattern"] != Pattern {
		t.Fatalf("endpointSelector = %#v, want an anyOf of the reference and the object", node)
	}
	if _, ok := branches[1].(map[string]any)["properties"]; !ok {
		t.Errorf("the object should be kept, got %#v", branches[1])
	}
}

func TestRefs_AnArrayAcceptsReferencesAsItems(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"dependsOn": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type":       "object",
					"properties": map[string]any{"name": map[string]any{"type": "string"}},
				},
			},
		},
	}
	m := Refs{"dependsOn": {Kinds: []string{"fluxHelmReleases"}, As: "helmReleaseRef"}}

	got, err := m.Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	node := property(got.Schema, "dependsOn")
	if node["type"] != "array" {
		t.Errorf("type = %#v, want it to stay an array", node["type"])
	}
	items, _ := node["items"].(map[string]any)
	branches, _ := items["anyOf"].([]any)
	if len(branches) != 2 || branches[0].(map[string]any)["pattern"] != Pattern {
		t.Fatalf("items = %#v, want an anyOf of the reference and the item", items)
	}
	if branches[1].(map[string]any)["type"] != "object" {
		t.Errorf("the item should be kept, got %#v", branches[1])
	}
}

func TestRefs_AnObjectNamedByAOneOfOfRequiredIsStillRelaxed(t *testing.T) {
	// the Cilium policies: `endpointSelector` is a property, and a `oneOf` of `required` names it again with `{}`
	schema := routeSchema()
	schema["oneOf"] = []any{
		map[string]any{
			"properties": map[string]any{"endpointSelector": map[string]any{}},
			"required":   []any{"endpointSelector"},
		},
	}
	m := Refs{"endpointSelector": {Kinds: []string{"deployments"}, As: "podSelector"}}

	got, err := m.Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	node := property(got.Schema, "endpointSelector")
	branches, _ := node["anyOf"].([]any)
	if len(branches) != 2 || branches[0].(map[string]any)["pattern"] != Pattern {
		t.Fatalf("endpointSelector = %#v, want an anyOf of the reference and the object", node)
	}
	placeholder := property(got.Schema["oneOf"].([]any)[0].(map[string]any), "endpointSelector")
	if len(placeholder) != 0 {
		t.Errorf("the name of the oneOf should be left as is, got %#v", placeholder)
	}
}

func TestRefs_NothingConfiguredReportsNothing(t *testing.T) {
	got, err := (Refs{}).Mutate(routeSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := got.TemplateArgs["refs"]; ok {
		t.Errorf("refs should not be reported, got %q", got.TemplateArgs["refs"])
	}
	if _, ok := property(got.Schema, "endpointSelector")["anyOf"]; ok {
		t.Errorf("the schema should be unchanged, got %#v", got.Schema)
	}
}

func TestRefs_RejectsWrongConfiguration(t *testing.T) {
	for name, m := range map[string]Refs{
		"unknown path":       {"nope": {Kinds: []string{"services"}, As: "name"}},
		"unknown projection": {"parentRefs": {Kinds: []string{"services"}, As: "nope"}},
		"no kinds":           {"parentRefs": {As: "gatewayRef"}},
		"not a string":       {"endpointSelector": {Kinds: []string{"services"}, As: "name"}},
	} {
		if _, err := m.Mutate(routeSchema()); err == nil {
			t.Errorf("%s: expected an error, got none", name)
		}
	}
}
