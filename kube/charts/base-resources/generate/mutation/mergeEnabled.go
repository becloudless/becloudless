package mutation

import "maps"

// MergeEnabled merges the well-known "enabled" field (handled by
// resources.renderResourceKind) into the schema's properties, taking
// precedence over any same-named property already present. Setting
// `enabled: false` on a resource instance excludes it from the rendered
// output entirely; it defaults to true when unset.
type MergeEnabled struct{}

func (MergeEnabled) Mutate(schema map[string]any, _ *Entry) (map[string]any, error) {
	mergedProps := map[string]any{}
	if p, ok := schema["properties"].(map[string]any); ok {
		maps.Copy(mergedProps, p)
	}
	mergedProps["enabled"] = map[string]any{
		"type":        "boolean",
		"description": "Whether to render this resource. Defaults to true.",
	}
	schema["properties"] = mergedProps
	schema["type"] = "object"
	return schema, nil
}
