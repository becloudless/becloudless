package mutations

// ArraysToMaps recursively converts array-type schema nodes into maps keyed
// by an arbitrary string id, working around Helm's inability to
// deep-merge arrays of objects the way .Values.resources.<kind>.<id> and
// .Values.defaults.resources.<kind> require. Ignore lists schema paths
// (see walkSchemaNodesWithPath) to leave as plain arrays instead (e.g. a
// container's string-typed command/args), declared per-resource-kind in
// resources.yaml as mutations.arraysToMaps.ignore.
type ArraysToMaps struct {
	Ignore []string `yaml:"ignore"`
}

func (m ArraysToMaps) Mutate(schema map[string]any) (MutationResult, error) {
	ignore := map[string]bool{}
	for _, path := range m.Ignore {
		ignore[path] = true
	}

	walkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if ignore[path] {
			return
		}
		convertArrayNodeToMap(node)
	})
	return MutationResult{Schema: schema}, nil
}

func convertArrayNodeToMap(node map[string]any) {
	if !schemaTypeIncludes(node["type"], "array") {
		return
	}
	items, ok := node["items"].(map[string]any)
	if !ok {
		return
	}

	node["type"] = replaceSchemaType(node["type"], "array", "object")
	node["additionalProperties"] = items
	delete(node, "items")
	delete(node, "minItems")
	delete(node, "maxItems")
	delete(node, "uniqueItems")
	delete(node, "x-kubernetes-list-type")
	delete(node, "x-kubernetes-list-map-keys")
}
