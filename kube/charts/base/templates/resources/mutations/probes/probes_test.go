package probes

import (
	"testing"
)

func probeSchema() map[string]any {
	probe := func() map[string]any {
		return map[string]any{
			"type": "object",
			"properties": map[string]any{
				"periodSeconds": map[string]any{"type": "integer"},
				"httpGet":       map[string]any{"type": "object"},
			},
		}
	}
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"containers": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"livenessProbe":  probe(),
						"readinessProbe": probe(),
						"startupProbe":   probe(),
						// not a probe: no timing fields
						"lifecycle": map[string]any{
							"type": "object",
							"properties": map[string]any{
								"postStart": map[string]any{"type": "object"},
							},
						},
					},
				},
			},
		},
	}
}

func TestProbes_AddsEnabledToEveryProbe(t *testing.T) {
	got, err := (Probes{}).Mutate(probeSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	containers := got.Schema["properties"].(map[string]any)["containers"].(map[string]any)
	props := containers["items"].(map[string]any)["properties"].(map[string]any)
	for _, name := range []string{"livenessProbe", "readinessProbe", "startupProbe"} {
		probeProps := props[name].(map[string]any)["properties"].(map[string]any)
		enabled, ok := probeProps["enabled"].(map[string]any)
		if !ok {
			t.Fatalf("%s.enabled is missing", name)
		}
		if enabled["type"] != "boolean" {
			t.Errorf("%s.enabled.type = %v, want %q", name, enabled["type"], "boolean")
		}
		if _, ok := probeProps["periodSeconds"]; !ok {
			t.Errorf("%s.periodSeconds should be kept", name)
		}
	}

	lifecycle := props["lifecycle"].(map[string]any)["properties"].(map[string]any)
	if _, ok := lifecycle["enabled"]; ok {
		t.Errorf("lifecycle must not get an enabled field")
	}

	want := `(list "containers.livenessProbe" "containers.readinessProbe" "containers.startupProbe")`
	if got.TemplateArgs["probePaths"] != want {
		t.Errorf("probePaths = %s, want %s", got.TemplateArgs["probePaths"], want)
	}
}

func TestProbes_IgnoresProbeFieldsNotShapedLikeProbes(t *testing.T) {
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"livenessProbe": map[string]any{
				"type":       "object",
				"properties": map[string]any{"foo": map[string]any{"type": "string"}},
			},
		},
	}
	got, err := (Probes{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	probeProps := got.Schema["properties"].(map[string]any)["livenessProbe"].(map[string]any)["properties"].(map[string]any)
	if _, ok := probeProps["enabled"]; ok {
		t.Errorf("a field not shaped like a probe must be left alone")
	}
	if got.TemplateArgs["probePaths"] != "(list )" {
		t.Errorf("probePaths = %s, want (list )", got.TemplateArgs["probePaths"])
	}
}
