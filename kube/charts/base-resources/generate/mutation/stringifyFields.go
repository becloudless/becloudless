package mutation

import (
	"fmt"
	"strings"
)

// StringifyFields relaxes the schema of the fields declared via the
// "stringifyFields" mutation config's "fields" option in resources.yaml:
//
//	mutations:
//	  stringifyFields:
//	    fields:
//	      - data
//
// so their values may be either a plain string or an arbitrary YAML/JSON
// node (object, array, number, bool), instead of being restricted to a
// string as upstream k8s declares (e.g. ConfigMap.data is a
// map[string]string). At render time, any non-string value given is
// serialized to a YAML string before being handed to Kubernetes (see
// templates/_renderAll.tpl and templates/_stringifyFields.tpl), so this
// only loosens the authoring-time schema used for .Values
// validation/editor hints, not what's actually sent to the API server.
//
// A node is affected if its schema path (see walkSchemaNodesWithPath)
// exactly matches one of the declared fields and it already declares a
// map-like "additionalProperties" schema (e.g. ConfigMap's "data":
// {"type": "object", "additionalProperties": {"type": "string"}}).
func StringifyFields(schema map[string]interface{}, e *Entry) (map[string]interface{}, error) {
	fieldList := e.ConfigList("stringifyFields", "fields")
	if len(fieldList) == 0 {
		return schema, nil
	}
	fields := map[string]bool{}
	quoted := make([]string, len(fieldList))
	for i, path := range fieldList {
		fields[path] = true
		quoted[i] = fmt.Sprintf("%q", path)
	}
	e.AddTemplateArg("stringifyFields", fmt.Sprintf("(list %s)", strings.Join(quoted, " ")))

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
