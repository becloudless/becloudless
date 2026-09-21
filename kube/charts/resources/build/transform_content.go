package main

import "fmt"

// extractContentTransform selects the relevant portion of a kind's full k8s
// JSON schema for use as the instance schema under
// .Values.resources.<name>.<id>:
//   - e.contentIsSpec: true  -> the schema's own top-level "spec" property
//   - e.contentIsSpec: false -> the schema's top-level properties, minus
//     apiVersion/kind/metadata/status (and "required" filtered the same way)
func extractContentTransform(kindSchema map[string]interface{}, e *entry) (map[string]interface{}, error) {
	if e.contentIsSpec {
		props, _ := kindSchema["properties"].(map[string]interface{})
		spec, _ := props["spec"].(map[string]interface{})
		if spec == nil {
			return nil, fmt.Errorf("%s: expected top-level \"spec\" property in schema", e.name)
		}
		return spec, nil
	}

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

// stripRequiredTransform moves the schema's top-level "required" list (if
// any) out of the schema and into e.required, since
// .Values.resources.<name>.<id> and .Values.defaults.resources.<name> share
// this exact schema and a defaults.resources entry - a partial overlay -
// shouldn't be forced to satisfy "required" on its own. The extracted fields
// are instead enforced at render time on the merged resource (see
// generateTemplate and templates/_requireFields.tpl).
func stripRequiredTransform(schema map[string]interface{}, e *entry) (map[string]interface{}, error) {
	var required []string
	if req, ok := schema["required"].([]interface{}); ok {
		for _, r := range req {
			if s, _ := r.(string); s != "" {
				required = append(required, s)
			}
		}
	}
	delete(schema, "required")
	e.required = required
	return schema, nil
}

// mergeMetadataTransform merges the well-known metadata fields (handled by
// resources.generic.computeMetadata / resources.generic.computeName) into
// the schema's properties, taking precedence over any same-named property
// already present.
func mergeMetadataTransform(schema map[string]interface{}, _ *entry) (map[string]interface{}, error) {
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
// resources.generic.computeMetadata / resources.generic.computeName. They're
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
