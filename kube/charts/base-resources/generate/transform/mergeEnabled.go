package transform

// MergeEnabled merges the well-known "enabled" field (handled by
// resources.generic.renderAll) into the schema's properties, taking
// precedence over any same-named property already present. Setting
// `enabled: false` on a resource instance excludes it from the rendered
// output entirely; it defaults to true when unset.
func MergeEnabled(schema map[string]interface{}, _ *Entry) (map[string]interface{}, error) {
	mergedProps := map[string]interface{}{}
	if p, ok := schema["properties"].(map[string]interface{}); ok {
		for k, v := range p {
			mergedProps[k] = v
		}
	}
	mergedProps["enabled"] = map[string]interface{}{
		"type":        "boolean",
		"description": "Whether to render this resource. Defaults to true.",
	}
	schema["properties"] = mergedProps
	schema["type"] = "object"
	return schema, nil
}
