package mutation

// NormalizeIntOrString fixes up schema nodes marked
// "x-kubernetes-int-or-string": true whose "anyOf" is JSON null rather than
// the pair of alternatives Kubernetes' own OpenAPI v3 spec normally
// resolves it to. Some upstream CRD manifests (fetched and parsed as-is,
// unlike Kubernetes' own OpenAPI v3 endpoint, which resolves this
// server-side) leave "anyOf: null" as a literal placeholder for this
// extension, relying on API server-side patching - which makes the field's
// schema invalid against the JSON Schema meta-schema itself ("anyOf", when
// present, must be an array), which in turn made Helm reject the (now
// validated) chart-root values.schema.json outright. Fixed here, generically,
// rather than special-cased per resource kind, since any future CRD could
// exhibit the same placeholder.
func NormalizeIntOrString(schema map[string]interface{}, e *Entry) (map[string]interface{}, error) {
	walkSchemaNodes(schema, func(node map[string]interface{}) {
		if node["x-kubernetes-int-or-string"] != true {
			return
		}
		if anyOf, ok := node["anyOf"]; ok && anyOf != nil {
			return
		}
		node["anyOf"] = []interface{}{
			map[string]interface{}{"type": "integer"},
			map[string]interface{}{"type": "string"},
		}
	})
	return schema, nil
}
