package transform

// walkSchemaNodes recursively visits every nested JSON-schema object found
// under node - via "properties", "additionalProperties", "items" and
// "oneOf"/"anyOf"/"allOf" - post-order (children before their parent), then
// finally visits node itself. Visit implementations are expected to mutate
// schema maps in place.
func walkSchemaNodes(node interface{}, visit func(map[string]interface{})) {
	m, ok := node.(map[string]interface{})
	if !ok {
		return
	}

	if props, ok := m["properties"].(map[string]interface{}); ok {
		for _, v := range props {
			walkSchemaNodes(v, visit)
		}
	}
	if additionalProps, ok := m["additionalProperties"].(map[string]interface{}); ok {
		walkSchemaNodes(additionalProps, visit)
	}
	if items, ok := m["items"].(map[string]interface{}); ok {
		walkSchemaNodes(items, visit)
	}
	for _, key := range []string{"oneOf", "anyOf", "allOf"} {
		if list, ok := m[key].([]interface{}); ok {
			for _, v := range list {
				walkSchemaNodes(v, visit)
			}
		}
	}

	visit(m)
}

// walkSchemaNodesWithPath behaves like walkSchemaNodes, but also passes each
// visited node's schema path to visit: a dot-joined sequence of property
// names leading to it from root (path "" for root itself). Array "items"
// and map "additionalProperties" indirections don't contribute a path
// segment of their own, so e.g. a "command" property nested under an
// array-of-objects "containers" property gets the path
// "containers.command", regardless of how many container instances exist
// or whether "containers" itself has been converted to a map (see
// ArraysToMaps) by the time this runs.
func walkSchemaNodesWithPath(node interface{}, path string, visit func(node map[string]interface{}, path string)) {
	m, ok := node.(map[string]interface{})
	if !ok {
		return
	}

	if props, ok := m["properties"].(map[string]interface{}); ok {
		for name, v := range props {
			childPath := name
			if path != "" {
				childPath = path + "." + name
			}
			walkSchemaNodesWithPath(v, childPath, visit)
		}
	}
	if additionalProps, ok := m["additionalProperties"].(map[string]interface{}); ok {
		walkSchemaNodesWithPath(additionalProps, path, visit)
	}
	if items, ok := m["items"].(map[string]interface{}); ok {
		walkSchemaNodesWithPath(items, path, visit)
	}
	for _, key := range []string{"oneOf", "anyOf", "allOf"} {
		if list, ok := m[key].([]interface{}); ok {
			for _, v := range list {
				walkSchemaNodesWithPath(v, path, visit)
			}
		}
	}

	visit(m, path)
}

// schemaTypeIncludes reports whether a JSON schema "type" value - either a
// single string or an array of strings (e.g. ["object", "null"]) - includes
// want.
func schemaTypeIncludes(t interface{}, want string) bool {
	switch v := t.(type) {
	case string:
		return v == want
	case []interface{}:
		for _, item := range v {
			if s, _ := item.(string); s == want {
				return true
			}
		}
	}
	return false
}

// replaceSchemaType replaces occurrences of "from" with "to" in a JSON
// schema "type" value, preserving whether it was a single string or an
// array of strings.
func replaceSchemaType(t interface{}, from, to string) interface{} {
	switch v := t.(type) {
	case string:
		if v == from {
			return to
		}
		return v
	case []interface{}:
		out := make([]interface{}, len(v))
		for i, item := range v {
			if s, _ := item.(string); s == from {
				out[i] = to
			} else {
				out[i] = item
			}
		}
		return out
	}
	return t
}
