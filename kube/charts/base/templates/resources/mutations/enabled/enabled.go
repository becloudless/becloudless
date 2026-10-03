package enabled

import (
	"maps"

	"resourceschart/templates/resources/mutations"
)

type Enabled struct{}

func (Enabled) Mutate(schema map[string]any) (mutations.MutationResult, error) {
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
	return mutations.MutationResult{Schema: schema}, nil
}
