package mutation

// MergeMetadata merges the well-known metadata fields (handled by
// resources.computeMetadata / resources.computeName) into
// the schema's properties, taking precedence over any same-named property
// already present.
func MergeMetadata(schema map[string]interface{}, _ *Entry) (map[string]interface{}, error) {
	mergedProps := map[string]interface{}{}
	if p, ok := schema["properties"].(map[string]interface{}); ok {
		for k, v := range p {
			mergedProps[k] = v
		}
	}
	for k, v := range metadataSchemaProperties() {
		mergedProps[k] = v
	}
	schema["properties"] = mergedProps
	schema["type"] = "object"
	return schema, nil
}

// metadataSchemaProperties are the well-known fields handled by
// resources.computeMetadata / resources.computeName. They're
// injected into every resource kind's instance schema, and take precedence
// over any same-named property coming from the kind's own k8s JSON schema.
func metadataSchemaProperties() map[string]interface{} {
	return map[string]interface{}{
		"nameOverride": map[string]interface{}{
			"type":        "string",
			"description": "Replaces just the id part of the computed resource name (<Release.Name>-<id>).",
		},
		"fullNameOverride": map[string]interface{}{
			"type":        "string",
			"description": "Replaces the entire computed resource name, ignoring the release name and id.",
		},
		"namespace": map[string]interface{}{
			"type":        "string",
			"description": "metadata.namespace for this resource. Defaults to the release namespace.",
		},
		"labels": map[string]interface{}{
			"type":                 "object",
			"description":          "metadata.labels for this resource.",
			"additionalProperties": map[string]interface{}{"type": "string"},
		},
		"annotations": map[string]interface{}{
			"type":                 "object",
			"description":          "metadata.annotations for this resource.",
			"additionalProperties": map[string]interface{}{"type": "string"},
		},
	}
}
