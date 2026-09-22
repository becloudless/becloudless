package transform

// ArraysToMaps recursively converts every array-type schema node that
// declares an "items" schema into an object/map keyed by an arbitrary
// string id, in line with this chart's convention of representing
// collections as maps keyed by id (e.g. .Values.resources.<kind>.<id>)
// rather than as arrays. The array's "items" schema becomes the map's
// "additionalProperties" schema, and array-only keywords are dropped.
//
// A node is left untouched (kept as a plain array) if its schema path (see
// walkSchemaNodesWithPath) is listed in e's "arraysToMaps" "ignore" config:
//
//	transformer:
//	  arraysToMaps:
//	    ignore:
//	      - path1
//	      - path2
//
// This is needed for array fields whose items aren't naturally keyable by
// an arbitrary id, e.g. a container's "command"/"args" ([]string): without
// an ignore entry these would otherwise be (incorrectly) turned into maps
// like every other array field.
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
