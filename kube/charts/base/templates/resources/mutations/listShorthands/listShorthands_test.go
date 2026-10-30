package listShorthands

import "testing"

func toPortsSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"egress": map[string]any{
				"type": "object", // converted from an array by ArraysToMaps
				"additionalProperties": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"toPorts": map[string]any{
							"type": "object",
							"additionalProperties": map[string]any{
								"type": "object",
								"properties": map[string]any{
									"ports": map[string]any{"type": "object"},
								},
							},
						},
					},
				},
			},
		},
	}
}

func toPorts(schema map[string]any) map[string]any {
	rule := schema["properties"].(map[string]any)["egress"].(map[string]any)["additionalProperties"].(map[string]any)
	return rule["properties"].(map[string]any)["toPorts"].(map[string]any)
}

func TestListShorthands_TheSchemaAcceptsAListOfScalarsAndReportsThePath(t *testing.T) {
	m := ListShorthands{"egress.toPorts": {Key: "main", Field: "ports"}}

	got, err := m.Mutate(toPortsSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	node := toPorts(got.Schema)
	types, _ := node["type"].([]any)
	if len(types) != 2 || types[0] != "object" || types[1] != "array" {
		t.Errorf("type = %#v, want object and array", node["type"])
	}
	items, _ := node["items"].(map[string]any)
	itemTypes, _ := items["type"].([]any)
	if len(itemTypes) != 2 || itemTypes[0] != "integer" || itemTypes[1] != "string" {
		t.Errorf("items = %#v, want integers and strings", node["items"])
	}
	if _, ok := node["additionalProperties"].(map[string]any); !ok {
		t.Errorf("additionalProperties should be kept, got %#v", node["additionalProperties"])
	}
	want := `(dict "egress.toPorts" (dict "key" "main" "field" "ports"))`
	if got.TemplateArgs["listShorthands"] != want {
		t.Errorf("listShorthands = %q, want %q", got.TemplateArgs["listShorthands"], want)
	}
}

func TestListShorthands_NothingConfiguredReportsNothing(t *testing.T) {
	got, err := (ListShorthands{}).Mutate(toPortsSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := got.TemplateArgs["listShorthands"]; ok {
		t.Errorf("listShorthands should not be reported, got %q", got.TemplateArgs["listShorthands"])
	}
	if toPorts(got.Schema)["type"] != "object" {
		t.Errorf("the schema should be unchanged, got %#v", toPorts(got.Schema))
	}
}

func TestListShorthands_RejectsUnknownPathOrField(t *testing.T) {
	for name, m := range map[string]ListShorthands{
		"unknown path":  {"nope": {Key: "main", Field: "ports"}},
		"unknown field": {"egress.toPorts": {Key: "main", Field: "nope"}},
		"no key":        {"egress.toPorts": {Field: "ports"}},
		"no field":      {"egress.toPorts": {Key: "main"}},
	} {
		if _, err := m.Mutate(toPortsSchema()); err == nil {
			t.Errorf("%s: expected an error, got none", name)
		}
	}
}
