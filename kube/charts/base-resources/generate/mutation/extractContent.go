package mutation

import "fmt"

// ExtractContent selects the relevant portion of a kind's full k8s JSON
// schema for use as the instance schema under
// .Values.resources.<name>.<id>:
//   - by default -> the schema's own top-level "spec" property
//   - if the "contentIsOutOfSpec" mutation is declared for this kind
//     (see Entry.HasMutation) -> the schema's top-level properties,
//     minus apiVersion/kind/metadata/status (and "required" filtered the
//     same way), for kinds whose content isn't wrapped in a "spec" of its
//     own (e.g. ConfigMap, Secret, ServiceAccount)
func ExtractContent(kindSchema map[string]interface{}, e *Entry) (map[string]interface{}, error) {
	if !e.HasMutation("contentIsOutOfSpec") {
		props, _ := kindSchema["properties"].(map[string]interface{})
		spec, _ := props["spec"].(map[string]interface{})
		if spec == nil {
			return nil, fmt.Errorf("%s: expected top-level \"spec\" property in schema", e.Name)
		}
		return spec, nil
	}

	e.AddTemplateArg("contentIsSpec", "false")

	props, _ := kindSchema["properties"].(map[string]interface{})
	contentProps := map[string]interface{}{}
	for k, v := range props {
		if k == "apiVersion" || k == "kind" || k == "metadata" || k == "status" {
			continue
		}
		contentProps[k] = v
	}
	instance := map[string]interface{}{
		"type":       "object",
		"properties": contentProps,
	}
	if req, ok := kindSchema["required"].([]interface{}); ok {
		var filtered []interface{}
		for _, r := range req {
			if s, _ := r.(string); s != "apiVersion" && s != "kind" && s != "metadata" && s != "status" {
				filtered = append(filtered, r)
			}
		}
		if len(filtered) > 0 {
			instance["required"] = filtered
		}
	}
	return instance, nil
}
