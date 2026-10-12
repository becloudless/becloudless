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
type ArraysToMaps struct {
	Ignore []string `yaml:"ignore"`
}

func (m ArraysToMaps) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	ignore := map[string]bool{}
	for _, path := range m.Ignore {
		ignore[path] = true
	}

	var convertedPaths []string
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if ignore[path] {
			return
		}
		if convertArrayNodeToMap(node) {
			convertedPaths = append(convertedPaths, path)
		}
	})

	sort.Strings(convertedPaths)
	quoted := make([]string, len(convertedPaths))
	for i, path := range convertedPaths {
		quoted[i] = fmt.Sprintf("%q", path)
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: map[string]string{"arrayPaths": fmt.Sprintf("(list %s)", strings.Join(quoted, " "))},
	}, nil
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
