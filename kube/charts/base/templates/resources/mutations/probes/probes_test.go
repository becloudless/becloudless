package probes

import (
	"strings"
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

func probeWithHandlers() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"periodSeconds": map[string]any{"type": "integer"},
			"httpGet": map[string]any{
				"type":     "object",
				"required": []any{"port"},
				"properties": map[string]any{
					"path": map[string]any{"type": "string"},
					"port": map[string]any{"description": "Name or number of the port."},
				},
			},
			"tcpSocket": map[string]any{
				"type":     "object",
				"required": []any{"port"},
				"properties": map[string]any{
					"port": map[string]any{"description": "Name or number of the port."},
				},
			},
			"exec": map[string]any{
				"type":       "object",
				"properties": map[string]any{"command": map[string]any{"type": "array"}},
			},
		},
	}
}

func containerSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"containers": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"livenessProbe":  probeWithHandlers(),
						"readinessProbe": probeWithHandlers(),
						"startupProbe":   probeWithHandlers(),
						"lifecycle": map[string]any{
							"type":       "object",
							"properties": map[string]any{"postStart": map[string]any{"type": "object"}},
						},
					},
				},
			},
		},
	}
}

func containerProps(schema map[string]any) map[string]any {
	containers := schema["properties"].(map[string]any)["containers"].(map[string]any)
	return containers["items"].(map[string]any)["properties"].(map[string]any)
}

func TestProbes_ThePortOfTheHandlersIsOptional(t *testing.T) {
	got, err := (Probes{}).Mutate(containerSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	for _, name := range []string{"livenessProbe", "readinessProbe", "startupProbe"} {
		probeProps := containerProps(got.Schema)[name].(map[string]any)["properties"].(map[string]any)
		for _, handler := range []string{"httpGet", "tcpSocket"} {
			node := probeProps[handler].(map[string]any)
			if required, ok := node["required"]; ok {
				t.Errorf("%s.%s.required = %v, want none: the port is optional", name, handler, required)
			}
			port := node["properties"].(map[string]any)["port"].(map[string]any)
			if description := port["description"].(string); !strings.Contains(description, "Defaults to the only port") {
				t.Errorf("%s.%s.port.description = %q, want the default explained", name, handler, description)
			}
		}
	}
}

func TestProbes_ContainersGetTheSharedProbe(t *testing.T) {
	got, err := (Probes{}).Mutate(containerSchema())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	props := containerProps(got.Schema)
	shared, ok := props["probe"].(map[string]any)
	if !ok {
		t.Fatalf("the container has no probe field: %v", props)
	}
	handlers := shared["properties"].(map[string]any)
	for _, name := range []string{"httpGet", "tcpSocket", "exec"} {
		if _, ok := handlers[name]; !ok {
			t.Errorf("probe.%s is missing", name)
		}
	}
	if _, ok := handlers["periodSeconds"]; ok {
		t.Errorf("probe must hold the handlers only, not the timings")
	}
	if _, ok := handlers["httpGet"].(map[string]any)["required"]; ok {
		t.Errorf("the port of the shared handler is optional too")
	}
	if _, ok := props["lifecycle"].(map[string]any)["properties"].(map[string]any)["probe"]; ok {
		t.Errorf("only the container gets the field")
	}
	for _, name := range []string{"livenessProbe", "readinessProbe", "startupProbe"} {
		if _, ok := props[name].(map[string]any)["properties"].(map[string]any)["probe"]; ok {
			t.Errorf("%s must not get the field", name)
		}
	}

	// the shared handlers are a copy: mutating them later must not change the probes
	handlers["httpGet"].(map[string]any)["type"] = "changed"
	liveness := props["livenessProbe"].(map[string]any)["properties"].(map[string]any)
	if liveness["httpGet"].(map[string]any)["type"] != "object" {
		t.Errorf("the shared handlers share their nodes with the probes")
	}
}
