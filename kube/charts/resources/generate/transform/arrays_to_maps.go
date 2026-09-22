package transform

// ArraysToMaps recursively converts every array-type schema node that
// declares an "items" schema into an object/map keyed by an arbitrary
// string id, in line with this chart's convention of representing
// collections as maps keyed by id (e.g. .Values.resources.<kind>.<id>)
// rather than as arrays. The array's "items" schema becomes the map's
// "additionalProperties" schema, and array-only keywords are dropped.
func ArraysToMaps(schema map[string]interface{}, _ *Entry) (map[string]interface{}, error) {
	walkSchemaNodes(schema, convertArrayNodeToMap)
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
