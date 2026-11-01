package build

import (
	"encoding/json"
	"strings"
	"testing"
)

func bigObject(description string) map[string]any {
	properties := map[string]any{}
	for _, name := range []string{"alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet"} {
		properties[name] = map[string]any{"type": "string", "description": "the " + name + " of the thing that is described here"}
	}
	return map[string]any{
		"type":                          "object",
		"description":                   description,
		"properties":                    properties,
		"x-kubernetes-preserve-unknown": true,
		"x-other":                       true,
	}
}

func testLocation(_, to string, tokens []string) string {
	return "#/$defs/" + to + pointerOf(tokens)
}

func TestOptimizeSchemas_RepeatedSubschemasPointToTheFirstOne(t *testing.T) {
	a := schemaDoc{name: "a", root: map[string]any{"properties": map[string]any{"spec": bigObject("first")}}}
	b := schemaDoc{name: "b", root: map[string]any{"properties": map[string]any{"other/spec": bigObject("second")}}}

	if err := optimizeSchemas([]schemaDoc{a, b}, testLocation, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	spec := a.root["properties"].(map[string]any)["spec"].(map[string]any)
	if _, ok := spec["properties"]; !ok {
		t.Errorf("the first occurrence should stay in place, got %#v", spec)
	}
	if _, ok := spec["x-other"]; !ok {
		t.Errorf("only the x-kubernetes- keywords are removed")
	}
	if _, ok := spec["x-kubernetes-preserve-unknown"]; ok {
		t.Errorf("the x-kubernetes- keywords should be removed")
	}

	other := b.root["properties"].(map[string]any)["other/spec"].(map[string]any)
	want := map[string]any{"$ref": "#/$defs/a/properties/spec", "description": "second"}
	gotJSON, _ := json.Marshal(other)
	wantJSON, _ := json.Marshal(want)
	if string(gotJSON) != string(wantJSON) {
		t.Errorf("the repeated occurrence = %s, want %s", gotJSON, wantJSON)
	}
}

func TestOptimizeSchemas_ExtensionsAreRemoved(t *testing.T) {
	a := schemaDoc{name: "a", root: map[string]any{
		"x-kubernetes-list-type": "map",
		"properties": map[string]any{
			"x-kubernetes-name": map[string]any{"type": "string", "x-kubernetes-int-or-string": true},
		},
	}}

	if err := optimizeSchemas([]schemaDoc{a}, testLocation, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	got, _ := json.Marshal(a.root)
	if want := `{"properties":{"x-kubernetes-name":{"type":"string"}}}`; string(got) != want {
		t.Errorf("schema = %s, want %s (a property named like an extension stays)", got, want)
	}
}

func TestOptimizeSchemas_SmallSubschemasStayInPlace(t *testing.T) {
	small := func() map[string]any { return map[string]any{"type": "string"} }
	a := schemaDoc{name: "a", root: map[string]any{"properties": map[string]any{"x": small()}}}
	b := schemaDoc{name: "b", root: map[string]any{"properties": map[string]any{"x": small()}}}

	if err := optimizeSchemas([]schemaDoc{a, b}, testLocation, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	got, _ := json.Marshal(b.root)
	if strings.Contains(string(got), "$ref") {
		t.Errorf("a small subschema should not be replaced: %s", got)
	}
}

func TestOptimizeSchemas_NestedRepeatsAreSharedOnce(t *testing.T) {
	wrap := func() map[string]any {
		return map[string]any{"type": "object", "properties": map[string]any{"inner": bigObject("inner")}}
	}
	a := schemaDoc{name: "a", root: map[string]any{"properties": map[string]any{"outer": wrap()}}}
	b := schemaDoc{name: "b", root: map[string]any{"properties": map[string]any{"outer": wrap(), "inner": bigObject("again")}}}

	if err := optimizeSchemas([]schemaDoc{a, b}, testLocation, nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	bProps := b.root["properties"].(map[string]any)
	if bProps["outer"].(map[string]any)["$ref"] != "#/$defs/a/properties/outer" {
		t.Errorf("outer = %#v, want a reference to the first one", bProps["outer"])
	}
	if bProps["inner"].(map[string]any)["$ref"] != "#/$defs/a/properties/outer/properties/inner" {
		t.Errorf("inner = %#v, want a reference into the first outer", bProps["inner"])
	}
}

func TestOptimizeSchemas_APointerThroughAReplacedNodeFails(t *testing.T) {
	a := schemaDoc{name: "a", root: map[string]any{"properties": map[string]any{"spec": bigObject("first")}}}
	b := schemaDoc{name: "b", root: map[string]any{"properties": map[string]any{"spec": bigObject("second")}}}

	err := optimizeSchemas([]schemaDoc{a, b}, testLocation, map[string][]string{"b": {"/properties/spec/properties/alpha"}})
	if err == nil || !strings.Contains(err.Error(), "$ref") {
		t.Fatalf("error = %v, want one about the $ref", err)
	}
}

func TestOrderDocs_PutsTheNamedDocumentsFirst(t *testing.T) {
	docs := []schemaDoc{{name: "a"}, {name: "deployments"}, {name: "b"}}

	var names []string
	for _, d := range orderDocs(docs, "deployments") {
		names = append(names, d.name)
	}
	if got := strings.Join(names, ","); got != "deployments,a,b" {
		t.Errorf("order = %s, want deployments,a,b", got)
	}
}
