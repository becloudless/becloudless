package mutation

import "maps"

// MergeMetadata merges the well-known metadata fields (handled by
// resources.computeMetadata / resources.computeName) into
// the schema's properties, taking precedence over any same-named property
// already present.
type MergeMetadata struct{}

func (MergeMetadata) Mutate(schema map[string]any, _ *Entry) (map[string]any, error) {
	mergedProps := map[string]any{}
	if p, ok := schema["properties"].(map[string]any); ok {
		maps.Copy(mergedProps, p)
	}
	maps.Copy(mergedProps, metadataSchemaProperties())
	schema["properties"] = mergedProps
	schema["type"] = "object"
	return schema, nil
}

// metadataSchemaProperties are the well-known fields handled by
// resources.computeMetadata / resources.computeName. They're
// injected into every resource kind's instance schema, and take precedence
// over any same-named property coming from the kind's own k8s JSON schema.
func metadataSchemaProperties() map[string]any {
	return map[string]any{
		"nameOverride": map[string]any{
			"type":        "string",
			"description": "Replaces just the id part of the computed resource name (<Release.Name>-<id>).",
		},
		"fullNameOverride": map[string]any{
			"type":        "string",
			"description": "Replaces the entire computed resource name, ignoring the release name and id.",
		},
		"namespace": map[string]any{
			"type":        "string",
			"description": "metadata.namespace for this resource. Defaults to the release namespace.",
		},
		"labels": map[string]any{
			"type":                 "object",
			"description":          "metadata.labels for this resource.",
			"additionalProperties": map[string]any{"type": "string"},
		},
		"annotations": map[string]any{
			"type":                 "object",
			"description":          "metadata.annotations for this resource.",
			"additionalProperties": map[string]any{"type": "string"},
		},
	}
}
