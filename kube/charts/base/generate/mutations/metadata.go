package mutations

import "maps"

type Metadata struct{}

func (Metadata) Mutate(schema map[string]any) (MutationResult, error) {
	mergedProps := map[string]any{}
	if p, ok := schema["properties"].(map[string]any); ok {
		maps.Copy(mergedProps, p)
	}
	maps.Copy(mergedProps, metadataSchemaProperties())
	schema["properties"] = mergedProps
	schema["type"] = "object"
	return MutationResult{Schema: schema}, nil
}

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
