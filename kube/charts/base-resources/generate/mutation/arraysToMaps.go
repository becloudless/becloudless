package mutation

func ArraysToMaps(schema map[string]interface{}, e *Entry) (map[string]interface{}, error) {
	ignore := map[string]bool{}
	for _, path := range e.ConfigList("arraysToMaps", "ignore") {
		ignore[path] = true
	}

	walkSchemaNodesWithPath(schema, "", func(node map[string]interface{}, path string) {
		if ignore[path] {
			return
		}
		convertArrayNodeToMap(node)
	})
	return schema, nil
}

func convertArrayNodeToMap(node map[string]interface{}) {
	if !schemaTypeIncludes(node["type"], "array") {
		return
	}
	items, ok := node["items"].(map[string]interface{})
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
