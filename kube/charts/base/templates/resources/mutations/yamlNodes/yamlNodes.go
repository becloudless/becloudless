package yamlNodes

import (
	"fmt"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// stringKeywords are the JSON schema keywords restricting the value of a string node, they make no sense for a node that
// can be a map or a list too.
var stringKeywords = []string{"enum", "const", "pattern", "format", "minLength", "maxLength"}

// YamlNodes relaxes the schema of the string fields declared via the "yamlNodes" mutation config's "fields" option in
// resources.yaml:
//
//	mutations:
//	  yamlNodes:
//	    fields:
//	      - postRenderers.kustomize.patches.patch
//
// so their value may be a plain string, or a YAML node (object, array), instead of being restricted to a string as the
// CRD declares (the kustomize patch of a HelmRelease is a string holding a YAML document). At render time a node given
// is serialized to a YAML string before being handed to Kubernetes (see _yamlNodes.tpl), a string is kept as it is.
// Unlike stringifyFields, which is for the values of a map of strings (ConfigMap.data), the field is a string itself,
// at any depth: the path is the one of WalkSchemaNodesWithPath (the maps of the arrays and the items add no segment).
type YamlNodes struct {
	Fields []string `yaml:"fields"`
}

func (m YamlNodes) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	if len(m.Fields) == 0 {
		return mutations.MutationResult{Schema: schema}, nil
	}
	fields := map[string]bool{}
	quoted := make([]string, len(m.Fields))
	for i, path := range m.Fields {
		fields[path] = true
		quoted[i] = fmt.Sprintf("%q", path)
	}

	found := map[string]bool{}
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if !fields[path] || !mutations.SchemaTypeIncludes(node["type"], "string") {
			return
		}
		found[path] = true
		for _, key := range stringKeywords {
			delete(node, key)
		}
		node["type"] = []any{"string", "object", "array"}
	})
	for _, path := range m.Fields {
		if !found[path] {
			return mutations.MutationResult{}, fmt.Errorf("yamlNodes: %q is not the path of a string field of the schema", path)
		}
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: map[string]string{"yamlNodes": fmt.Sprintf("(list %s)", strings.Join(quoted, " "))},
	}, nil
}
