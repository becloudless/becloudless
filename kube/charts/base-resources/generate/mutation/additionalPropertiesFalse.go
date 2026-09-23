package mutation

// AdditionalPropertiesFalse recursively sets "additionalProperties": false
// on every object-type schema node that declares its own "properties" but
// doesn't already constrain additionalProperties (via "additionalProperties"
// or "patternProperties"), closing the schema against unknown/typo'd
// fields. Nodes that already declare "additionalProperties" (e.g. free-form
// maps like ConfigMap's "data", or maps produced by ArraysToMaps) are left
// untouched.
type AdditionalPropertiesFalse struct{}

func (AdditionalPropertiesFalse) Mutate(schema map[string]any) (MutationResult, error) {
	walkSchemaNodes(schema, func(node map[string]any) {
		if !schemaTypeIncludes(node["type"], "object") {
			return
		}
		if _, hasProps := node["properties"]; !hasProps {
			return
		}
		if _, ok := node["additionalProperties"]; ok {
			return
		}
		if _, ok := node["patternProperties"]; ok {
			return
		}
		node["additionalProperties"] = false
	})
	return MutationResult{Schema: schema}, nil
}
