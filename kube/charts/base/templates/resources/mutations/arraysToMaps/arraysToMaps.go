package arraysToMaps

import (
	"fmt"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// ArraysToMaps recursively converts array-type schema nodes into maps keyed
// by an arbitrary string id, working around Helm's inability to
// deep-merge arrays of objects the way .Values.resources.<kind>.<id> and
// .Values.defaults.resources.<kind> require. Ignore lists schema paths
// (see walkSchemaNodesWithPath) to leave as plain arrays instead (e.g. a
// container's string-typed command/args), declared per-resource-kind in
// resources.yaml as mutations.arraysToMaps.ignore.
//
// Every converted path is reported back via MutationResult.TemplateArgs
// (key "arrayPaths"), so templates/mutations/_mapsToArrays.tpl can reverse
// the conversion at render time and emit valid Kubernetes arrays again.
//
// Disabled leaves every array as is (declared per-resource-kind in resources.yaml as
// mutations.arraysToMaps.disabled), for the resources whose arrays are better written as real arrays, ex: the
// ClusterPolicies of Kyverno, which are given as files. No path is reported then, nothing is reversed at render time.
//
// KeyFields sets a field of the items of a converted array to their key when they do not set it (declared per-resource-kind in
// resources.yaml as mutations.arraysToMaps.keyFields: the schema path of the array and the name of the field), ex: for the
// StringSecrets `fields.password: {}` is `fields: [{fieldName: password}]`. They are reported via
// MutationResult.TemplateArgs (key "keyFields"), for templates/mutations/_mapsToArrays.tpl.
type ArraysToMaps struct {
	Ignore    []string          `yaml:"ignore"`
	Disabled  bool              `yaml:"disabled"`
	KeyFields map[string]string `yaml:"keyFields"`
}

func (m ArraysToMaps) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	if m.Disabled {
		return mutations.MutationResult{
			Schema:       schema,
			TemplateArgs: map[string]string{"arrayPaths": "(list )"},
		}, nil
	}

	ignore := map[string]bool{}
	for _, path := range m.Ignore {
		ignore[path] = true
	}

	var convertedPaths []string
	keyFieldsFound := map[string]bool{}
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if ignore[path] {
			return
		}
		if convertArrayNodeToMap(node) {
			convertedPaths = append(convertedPaths, path)
			if field, ok := m.KeyFields[path]; ok && hasItemProperty(node, field) {
				keyFieldsFound[path] = true
			}
		}
	})

	for path, field := range m.KeyFields {
		if !keyFieldsFound[path] {
			return mutations.MutationResult{}, fmt.Errorf("keyFields %q: %q is not an array of objects with the property %q", path, path, field)
		}
	}

	sort.Strings(convertedPaths)
	quoted := make([]string, len(convertedPaths))
	for i, path := range convertedPaths {
		quoted[i] = fmt.Sprintf("%q", path)
	}

	templateArgs := map[string]string{"arrayPaths": fmt.Sprintf("(list %s)", strings.Join(quoted, " "))}
	if len(m.KeyFields) > 0 {
		keyFieldPaths := make([]string, 0, len(m.KeyFields))
		for path := range m.KeyFields {
			keyFieldPaths = append(keyFieldPaths, path)
		}
		sort.Strings(keyFieldPaths)
		pairs := make([]string, 0, len(keyFieldPaths))
		for _, path := range keyFieldPaths {
			pairs = append(pairs, fmt.Sprintf("%q %q", path, m.KeyFields[path]))
		}
		templateArgs["keyFields"] = fmt.Sprintf("(dict %s)", strings.Join(pairs, " "))
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: templateArgs,
	}, nil
}

// hasItemProperty reports whether the items of the converted array node (its additionalProperties) are objects that have
// the property.
func hasItemProperty(node map[string]any, field string) bool {
	items, ok := node["additionalProperties"].(map[string]any)
	if !ok {
		return false
	}
	props, ok := items["properties"].(map[string]any)
	if !ok {
		return false
	}
	_, ok = props[field]
	return ok
}

func convertArrayNodeToMap(node map[string]any) bool {
	if !mutations.SchemaTypeIncludes(node["type"], "array") {
		return false
	}
	items, ok := node["items"].(map[string]any)
	if !ok {
		return false
	}

	node["type"] = mutations.ReplaceSchemaType(node["type"], "array", "object")
	node["additionalProperties"] = items
	delete(node, "items")
	delete(node, "minItems")
	delete(node, "maxItems")
	delete(node, "uniqueItems")
	delete(node, "x-kubernetes-list-type")
	delete(node, "x-kubernetes-list-map-keys")
	return true
}
