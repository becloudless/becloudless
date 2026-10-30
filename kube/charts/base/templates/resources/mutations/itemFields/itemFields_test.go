package itemFields

import "testing"

func portsSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"ports": map[string]any{
				"type": "object",
				"additionalProperties": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"port":     map[string]any{"type": "string"},
						"protocol": map[string]any{"type": "string"},
					},
				},
			},
		},
	}
}

func TestItemFields_ReportsThePathsAsTemplateArg(t *testing.T) {
	m := ItemFields{"ports": {KeyField: "port", Defaults: map[string]string{"protocol": "TCP"}}}

	got, err := m.Mutate(portsSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := `(dict "ports" (dict "keyField" "port" "defaults" (dict "protocol" "TCP")))`
	if got.TemplateArgs["itemFields"] != want {
		t.Errorf("itemFields = %q, want %q", got.TemplateArgs["itemFields"], want)
	}
}

func TestItemFields_OnlyDefaults(t *testing.T) {
	m := ItemFields{"ports": {Defaults: map[string]string{"protocol": "TCP"}}}

	got, err := m.Mutate(portsSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := `(dict "ports" (dict "keyField" "" "defaults" (dict "protocol" "TCP")))`
	if got.TemplateArgs["itemFields"] != want {
		t.Errorf("itemFields = %q, want %q", got.TemplateArgs["itemFields"], want)
	}
}

func TestItemFields_NothingConfiguredReportsNothing(t *testing.T) {
	got, err := (ItemFields{}).Mutate(portsSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if _, ok := got.TemplateArgs["itemFields"]; ok {
		t.Errorf("itemFields should not be reported, got %q", got.TemplateArgs["itemFields"])
	}
}

func TestItemFields_RejectsUnknownPathOrProperty(t *testing.T) {
	for name, m := range map[string]ItemFields{
		"unknown path":             {"nope": {KeyField: "port"}},
		"unknown key field":        {"ports": {KeyField: "nope"}},
		"unknown default property": {"ports": {Defaults: map[string]string{"nope": "x"}}},
	} {
		if _, err := m.Mutate(portsSchema()); err == nil {
			t.Errorf("%s: expected an error, got none", name)
		}
	}
}
