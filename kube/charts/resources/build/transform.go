package main

// Transformer manipulates a resource kind's JSON schema as part of the
// build pipeline (see fetchAndTransformSchema). Each transformer receives
// the schema produced by the previous transformer in the pipeline -
// starting from the raw upstream k8s JSON schema - together with the entry
// describing the resource kind being processed, and returns the (possibly
// new) schema to hand to the next transformer.
//
// Transformers may mutate e (e.g. to record required fields, see
// stripRequiredTransform) since schema/resources/<name>.json itself never
// declares a top-level "required": .Values.resources.<kind>.<id> and
// .Values.defaults.resources.<kind> intentionally share this exact schema,
// and "required" is instead enforced at render time on the merged resource
// (see templates/_requireFields.tpl and generateTemplate).
type Transformer interface {
	Transform(schema map[string]interface{}, e *entry) (map[string]interface{}, error)
}

// TransformerFunc adapts a plain function to the Transformer interface.
type TransformerFunc func(schema map[string]interface{}, e *entry) (map[string]interface{}, error)

func (f TransformerFunc) Transform(schema map[string]interface{}, e *entry) (map[string]interface{}, error) {
	return f(schema, e)
}

// defaultTransformers is the pipeline applied - in order - to every fetched
// upstream k8s JSON schema to produce the final schema/resources/<name>.json:
//
//  1. extractContentTransform            - selects the relevant subset of
//     the upstream schema (either the "spec" property, or the top-level
//     properties minus apiVersion/kind/metadata/status), depending on
//     e.contentIsSpec.
//  2. stripRequiredTransform              - moves the top-level "required"
//     list out of the schema and into e.required.
//  3. mergeMetadataTransform              - merges in the well-known
//     metadata fields (nameOverride, fullNameOverride, namespace, labels,
//     annotations).
//  4. arraysToMapsTransform               - recursively converts array-type
//     schema nodes into maps keyed by an arbitrary string id.
//  5. additionalPropertiesFalseTransform  - recursively closes every
//     structured object node against unknown properties.
var defaultTransformers = []Transformer{
	TransformerFunc(extractContentTransform),
	TransformerFunc(stripRequiredTransform),
	TransformerFunc(mergeMetadataTransform),
	TransformerFunc(arraysToMapsTransform),
	TransformerFunc(additionalPropertiesFalseTransform),
}

// applyTransformers runs schema through each transformer in order, threading
// the result of one into the next.
func applyTransformers(transformers []Transformer, schema map[string]interface{}, e *entry) (map[string]interface{}, error) {
	var err error
	for _, t := range transformers {
		schema, err = t.Transform(schema, e)
		if err != nil {
			return nil, err
		}
	}
	return schema, nil
}

// walkSchemaNodes recursively visits every nested JSON-schema object found
// under node - via "properties", "additionalProperties", "items" and
// "oneOf"/"anyOf"/"allOf" - post-order (children before their parent), then
// finally visits node itself. Visit implementations are expected to mutate
// schema maps in place.
func walkSchemaNodes(node interface{}, visit func(map[string]interface{})) {
	m, ok := node.(map[string]interface{})
	if !ok {
		return
	}

	if props, ok := m["properties"].(map[string]interface{}); ok {
		for _, v := range props {
			walkSchemaNodes(v, visit)
		}
	}
	if additionalProps, ok := m["additionalProperties"].(map[string]interface{}); ok {
		walkSchemaNodes(additionalProps, visit)
	}
	if items, ok := m["items"].(map[string]interface{}); ok {
		walkSchemaNodes(items, visit)
	}
	for _, key := range []string{"oneOf", "anyOf", "allOf"} {
		if list, ok := m[key].([]interface{}); ok {
			for _, v := range list {
				walkSchemaNodes(v, visit)
			}
		}
	}

	visit(m)
}

// schemaTypeIncludes reports whether a JSON schema "type" value - either a
// single string or an array of strings (e.g. ["object", "null"]) - includes
// want.
func schemaTypeIncludes(t interface{}, want string) bool {
	switch v := t.(type) {
	case string:
		return v == want
	case []interface{}:
		for _, item := range v {
			if s, _ := item.(string); s == want {
				return true
			}
		}
	}
	return false
}

// replaceSchemaType replaces occurrences of "from" with "to" in a JSON
// schema "type" value, preserving whether it was a single string or an
// array of strings.
func replaceSchemaType(t interface{}, from, to string) interface{} {
	switch v := t.(type) {
	case string:
		if v == from {
			return to
		}
		return v
	case []interface{}:
		out := make([]interface{}, len(v))
		for i, item := range v {
			if s, _ := item.(string); s == from {
				out[i] = to
			} else {
				out[i] = item
			}
		}
		return out
	}
	return t
}
