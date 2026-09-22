package transform

// StringifyFields relaxes the schema of the fields declared in
// e.StringifyFields (see the generate package's resource.stringifyFields,
// set in resources.yaml) so their values may be either a plain string or an
// arbitrary YAML/JSON node (object, array, number, bool), instead of being
// restricted to a string as upstream k8s declares (e.g. ConfigMap.data is a
// map[string]string). At render time, any non-string value given is
// serialized to a YAML string before being handed to Kubernetes (see
// templates/_renderAll.tpl), so this only loosens the authoring-time schema
// used for .Values validation/editor hints, not what's actually sent to the
// API server.
//
// A node is affected if its schema path (see walkSchemaNodesWithPath)
// exactly matches one of e's declared StringifyFields and it already
// declares a map-like "additionalProperties" schema (e.g. ConfigMap's
// "data": {"type": "object", "additionalProperties": {"type": "string"}}).
func StringifyFields(schema map[string]interface{}, e *Entry) (map[string]interface{}, error) {
	if len(e.StringifyFields) == 0 {
		return schema, nil
	}
	fields := map[string]bool{}
	for _, path := range e.StringifyFields {
		fields[path] = true
	}

	walkSchemaNodesWithPath(schema, "", func(node map[string]interface{}, path string) {
		if !fields[path] {
			return
		}
		if _, ok := node["additionalProperties"]; !ok {
			return
		}
		node["additionalProperties"] = map[string]interface{}{}
	})
	return schema, nil
}
