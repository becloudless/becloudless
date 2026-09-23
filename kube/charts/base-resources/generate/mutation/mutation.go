package mutation

// Entry carries the subset of a resource kind's build-time metadata (see
// the generate package's own resource type in resource.go) that mutations
// need: just the kind's name, for error messages. Per-mutation
// configuration is instead carried directly on each Mutation value (see
// e.g. ArraysToMaps, StringifyFields) and wired in by the caller (see
// Pipeline). Mutations may also contribute render-time template arguments
// as a side effect (see AddTemplateArg).
type Entry struct {
	Name string

	// TemplateArgs holds the named arguments mutations have contributed
	// (via AddTemplateArg) to the dict passed to
	// templates/_renderAll.tpl's "resources.renderResourceKind" template at
	// render time (see the generate package's generateTemplate). Order
	// matches the order mutations ran in (see Pipeline), and therefore the
	// order args are called in.
	TemplateArgs []TemplateArg
}

// TemplateArg is one named argument a mutation contributes to the dict
// passed to "resources.renderResourceKind" for a resource kind (see
// Entry.TemplateArgs). Value is a raw Helm template expression (e.g.
// `false`, `(list "a" "b")`) spliced as-is into the generated
// templates/_generated.tpl, not a Go value.
type TemplateArg struct {
	Name  string
	Value string
}

// AddTemplateArg registers a named, render-time template argument (see
// Entry.TemplateArgs) for the generated "resources.renderResourceKind" call
// for this resource kind. Mutations use this to self-contribute additional
// render-time behavior alongside whatever build-time schema changes they
// make, instead of the generate package's generateTemplate needing to know
// about specific mutation names; see e.g. ExtractContent's "contentIsSpec"
// arg, StripRequired's "required" arg, and StringifyFields'
// "stringifyFields" arg.
func (e *Entry) AddTemplateArg(name, value string) {
	e.TemplateArgs = append(e.TemplateArgs, TemplateArg{Name: name, Value: value})
}

// Mutation manipulates a resource kind's JSON schema as part of the build
// pipeline. Each mutation receives the schema produced by the previous
// mutation in the pipeline - starting from the raw upstream k8s JSON schema
// - together with the Entry describing the resource kind being processed,
// and returns the (possibly new) schema to hand to the next mutation.
//
// Mutations may mutate e (e.g. to contribute a render-time template
// argument, see AddTemplateArg and the StripRequired mutation) since
// schema/resources/<name>.json itself never declares a top-level
// "required": .Values.resources.<kind>.<id> and .Values.defaults.resources.<kind>
// intentionally share this exact schema, and "required" is instead enforced
// at render time on the merged resource (see templates/_requireFields.tpl
// and the generate package's generateTemplate).
type Mutation interface {
	Mutate(schema map[string]any, e *Entry) (map[string]any, error)
}

// Pipeline returns the mutation pipeline applied - in order - to every
// fetched upstream k8s JSON schema to produce the final
// schema/resources/<name>.json:
//
//  1. extractContent             - selects the relevant subset of the
//     upstream schema: the schema's own top-level "spec" property by
//     default, or the top-level properties minus
//     apiVersion/kind/metadata/status, if extractContent.ContentIsOutOfSpec
//     is set (e.g. core kinds like ConfigMap/Secret/ServiceAccount that
//     have no "spec" of their own).
//  2. FlattenAllOf               - collapses "allOf" nodes (as produced by
//     resolving $ref pointers from Kubernetes' OpenAPI v3 spec) into flat
//     object schemas.
//  3. NormalizeIntOrString       - fixes up "x-kubernetes-int-or-string"
//     nodes whose "anyOf" is a literal JSON null (some upstream CRD
//     manifests leave this as a placeholder) into a proper
//     integer-or-string "anyOf" pair.
//  4. StripRequired              - moves the top-level "required" list out
//     of the schema and into a "required" template arg (see
//     Entry.AddTemplateArg).
//  5. MergeMetadata              - merges in the well-known metadata fields
//     (nameOverride, fullNameOverride, namespace, labels, annotations).
//  6. MergeEnabled               - merges in the well-known "enabled" field,
//     allowing a resource instance to be excluded from the rendered output
//     entirely.
//  7. arraysToMaps               - recursively converts array-type schema
//     nodes into maps keyed by an arbitrary string id, per
//     arraysToMaps.Ignore.
//  8. stringifyFields            - relaxes the schema of
//     stringifyFields.Fields so their values may be either a plain string
//     or an arbitrary YAML/JSON node.
//  9. AdditionalPropertiesFalse  - recursively closes every structured
//     object node against unknown properties.
//
// arraysToMaps and stringifyFields default to their zero value (no
// configuration) if nil.
func Pipeline(extractContent ExtractContent, arraysToMaps *ArraysToMaps, stringifyFields *StringifyFields) []Mutation {
	if arraysToMaps == nil {
		arraysToMaps = &ArraysToMaps{}
	}
	if stringifyFields == nil {
		stringifyFields = &StringifyFields{}
	}
	return []Mutation{
		extractContent,
		FlattenAllOf{},
		NormalizeIntOrString{},
		StripRequired{},
		MergeMetadata{},
		MergeEnabled{},
		*arraysToMaps,
		*stringifyFields,
		AdditionalPropertiesFalse{},
	}
}

// Apply runs schema through each mutation in order, threading the result of
// one into the next.
func Apply(mutations []Mutation, schema map[string]any, e *Entry) (map[string]any, error) {
	var err error
	for _, m := range mutations {
		schema, err = m.Mutate(schema, e)
		if err != nil {
			return nil, err
		}
	}
	return schema, nil
}
