package portMaps

import (
	"reflect"
	"testing"
)

func portSchema(nameProp string) map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"containers": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"ports": map[string]any{
							"type": "array",
							"items": map[string]any{
								"type":     "object",
								"required": []any{nameProp, "name"},
								"properties": map[string]any{
									"name":     map[string]any{"type": "string"},
									nameProp:   map[string]any{"type": "integer"},
									"protocol": map[string]any{"type": "string"},
								},
							},
						},
					},
				},
			},
		},
	}
}

func TestPortMaps_ConvertsNamedPortsArrayToMapKeyedByName(t *testing.T) {
	got, err := (PortMaps{}).Mutate(portSchema("containerPort"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	containers := got.Schema["properties"].(map[string]any)["containers"].(map[string]any)
	ports := containers["items"].(map[string]any)["properties"].(map[string]any)["ports"].(map[string]any)
	if ports["type"] != "object" {
		t.Errorf("ports.type = %v, want %q", ports["type"], "object")
	}
	if _, ok := ports["items"]; ok {
		t.Errorf("ports.items should have been removed, got %#v", ports["items"])
	}
	port := ports["additionalProperties"].(map[string]any)
	props := port["properties"].(map[string]any)
	if _, ok := props["name"]; ok {
		t.Errorf("the name property should have been removed, got %#v", props)
	}
	if _, ok := props["containerPort"]; !ok {
		t.Errorf("the containerPort property should have been kept, got %#v", props)
	}
	if !reflect.DeepEqual(port["required"], []any{"containerPort"}) {
		t.Errorf("required = %#v, want [containerPort]", port["required"])
	}

	// untouched: the containers array itself, left to ArraysToMaps
	if containers["type"] != "array" {
		t.Errorf("containers.type = %v, want %q", containers["type"], "array")
	}
	if got.TemplateArgs["portPaths"] != `(list "containers.ports")` {
		t.Errorf("portPaths = %s, want (list \"containers.ports\")", got.TemplateArgs["portPaths"])
	}
}

func TestPortMaps_ConvertsServicePorts(t *testing.T) {
	schema := map[string]any{
		"type":       "object",
		"properties": map[string]any{"ports": portSchema("port")["properties"].(map[string]any)["containers"].(map[string]any)["items"].(map[string]any)["properties"].(map[string]any)["ports"]},
	}
	got, err := (PortMaps{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.TemplateArgs["portPaths"] != `(list "ports")` {
		t.Errorf("portPaths = %s, want (list \"ports\")", got.TemplateArgs["portPaths"])
	}
}

func TestPortMaps_IgnoresPortsWithoutName(t *testing.T) {
	// NetworkPolicy style ports: no name, handled by ArraysToMaps
	schema := map[string]any{
		"type": "object",
		"properties": map[string]any{
			"ports": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"port":     map[string]any{"type": "integer"},
						"protocol": map[string]any{"type": "string"},
					},
				},
			},
		},
	}
	got, err := (PortMaps{}).Mutate(schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	ports := got.Schema["properties"].(map[string]any)["ports"].(map[string]any)
	if ports["type"] != "array" {
		t.Errorf("ports.type = %v, want %q", ports["type"], "array")
	}
	if got.TemplateArgs["portPaths"] != "(list )" {
		t.Errorf("portPaths = %s, want (list )", got.TemplateArgs["portPaths"])
	}
}
