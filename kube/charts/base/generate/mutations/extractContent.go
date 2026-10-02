package mutations

import "fmt"

// ExtractContent selects the relevant portion of a kind's full k8s JSON schema for use as the instance schema
type ExtractContent struct {
	ContentIsOutOfSpec bool `yaml:"contentIsOutOfSpec"`

	// KindName is the resource kind's name (e.g. "deployments"), used only
	// for the error returned when ContentIsOutOfSpec is false and the
	// schema unexpectedly has no top-level "spec" property.
	KindName string `yaml:"-"`
}

func (m ExtractContent) Mutate(kindSchema map[string]any) (MutationResult, error) {
	if !m.ContentIsOutOfSpec {
		props, _ := kindSchema["properties"].(map[string]any)
		spec, _ := props["spec"].(map[string]any)
		if spec == nil {
			return MutationResult{}, fmt.Errorf("%s: expected top-level \"spec\" property in schema", m.KindName)
		}
		return MutationResult{Schema: spec}, nil
	}

	props, _ := kindSchema["properties"].(map[string]any)
	contentProps := map[string]any{}
	for k, v := range props {
		if k == "apiVersion" || k == "kind" || k == "metadata" || k == "status" {
			continue
		}
		contentProps[k] = v
	}
	instance := map[string]any{
		"type":       "object",
		"properties": contentProps,
	}
	if req, ok := kindSchema["required"].([]any); ok {
		var filtered []any
		for _, r := range req {
			if s, _ := r.(string); s != "apiVersion" && s != "kind" && s != "metadata" && s != "status" {
				filtered = append(filtered, r)
			}
		}
		if len(filtered) > 0 {
			instance["required"] = filtered
		}
	}
	return MutationResult{
		Schema:       instance,
		TemplateArgs: map[string]string{"contentIsSpec": "false"},
	}, nil
}
