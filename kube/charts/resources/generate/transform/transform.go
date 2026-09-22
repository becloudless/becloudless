// Package transform implements the schema transformation pipeline applied
// to every fetched upstream k8s JSON schema to produce the final
// schema/resources/<name>.json (see the generate package's
// fetchAndTransformSchema).
package transform

// Entry carries the subset of a resource kind's build-time metadata (see
// the generate package's own entry type in crds.go) that transformers need:
// the kind's name (for error messages) and whether its schema content lives
// under a "spec" property. Transformers may also populate Required as a
// side effect (see the StripRequired transformer).
type Entry struct {
	Name          string
	ContentIsSpec bool
	Required      []string
}

// Transformer manipulates a resource kind's JSON schema as part of the
// build pipeline. Each transformer receives the schema produced by the
// previous transformer in the pipeline - starting from the raw upstream k8s
// JSON schema - together with the Entry describing the resource kind being
// processed, and returns the (possibly new) schema to hand to the next
// transformer.
//
// Transformers may mutate e (e.g. to record required fields, see the
// StripRequired transformer) since schema/resources/<name>.json itself
// never declares a top-level "required": .Values.resources.<kind>.<id> and
// .Values.defaults.resources.<kind> intentionally share this exact schema,
// and "required" is instead enforced at render time on the merged resource
// (see templates/_requireFields.tpl and the generate package's
// generateTemplate).
type Transformer interface {
	Transform(schema map[string]interface{}, e *Entry) (map[string]interface{}, error)
}

// TransformerFunc adapts a plain function to the Transformer interface.
type TransformerFunc func(schema map[string]interface{}, e *Entry) (map[string]interface{}, error)

func (f TransformerFunc) Transform(schema map[string]interface{}, e *Entry) (map[string]interface{}, error) {
	return f(schema, e)
}

// DefaultTransformers is the pipeline applied - in order - to every fetched
// upstream k8s JSON schema to produce the final schema/resources/<name>.json:
//
//  1. ExtractContent            - selects the relevant subset of the
//     upstream schema (either the "spec" property, or the top-level
//     properties minus apiVersion/kind/metadata/status), depending on
//     e.ContentIsSpec.
//  2. FlattenAllOf               - collapses "allOf" nodes (as produced by
//     resolving $ref pointers from Kubernetes' OpenAPI v3 spec) into flat
//     object schemas.
//  3. StripRequired              - moves the top-level "required" list out
//     of the schema and into e.Required.
//  4. MergeMetadata              - merges in the well-known metadata fields
//     (nameOverride, fullNameOverride, namespace, labels, annotations).
//  5. MergeEnabled               - merges in the well-known "enabled" field,
//     allowing a resource instance to be excluded from the rendered output
//     entirely.
//  6. ArraysToMaps               - recursively converts array-type schema
//     nodes into maps keyed by an arbitrary string id.
//  7. AdditionalPropertiesFalse  - recursively closes every structured
//     object node against unknown properties.
var DefaultTransformers = []Transformer{
	TransformerFunc(ExtractContent),
	TransformerFunc(FlattenAllOf),
	TransformerFunc(StripRequired),
	TransformerFunc(MergeMetadata),
	TransformerFunc(MergeEnabled),
	TransformerFunc(ArraysToMaps),
	TransformerFunc(AdditionalPropertiesFalse),
}

// Apply runs schema through each transformer in order, threading the result
// of one into the next.
func Apply(transformers []Transformer, schema map[string]interface{}, e *Entry) (map[string]interface{}, error) {
	var err error
	for _, t := range transformers {
		schema, err = t.Transform(schema, e)
		if err != nil {
			return nil, err
		}
	}
	return schema, nil
}
