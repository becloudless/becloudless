package templatedStrings

import "github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"

// TemplatePattern matches a string holding at least one Go template action,
// e.g. "{{ .Values.global.domain }}" or "https://{{ .Values.name }}/path".
// [\s\S] is used instead of "." so multi-line templates match too.
const TemplatePattern = `\{\{[\s\S]*\}\}`

// validationKeywords are the JSON schema keywords restricting the value of a
// string node. A templated value ("{{ ... }}") is rendered by tpl before
// reaching Kubernetes (see templates/resources/mutations/defaults), so
// before that it generally does not satisfy any of them.
var validationKeywords = []string{"enum", "const", "pattern", "format", "minLength", "maxLength"}

// TemplatedStrings relaxes the validation of the string fields so they also
// accept a chart template. Every string node carrying validation keywords
// (enum, const, pattern, format, minLength, maxLength):
//
//	{"type": "string", "format": "date-time"}
//
// is rewritten to accept either a value satisfying its original validation
// or a value containing a template action:
//
//	{"type": "string", "anyOf": [
//	  {"format": "date-time"},
//	  {"pattern": "\\{\\{[\\s\\S]*\\}\\}"}
//	]}
//
// The template is still validated: it must hold a well formed "{{" ... "}}"
// pair, so a plain value breaking the original validation keeps being
// rejected. Unconstrained string nodes are left untouched, since they already
// accept anything, as well as the nodes already declaring a combination
// ("anyOf", "oneOf", "allOf", "not"), which cannot be wrapped safely.
type TemplatedStrings struct{}

func (TemplatedStrings) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	mutations.WalkSchemaNodes(schema, func(node map[string]any) {
		if !mutations.SchemaTypeIncludes(node["type"], "string") {
			return
		}
		for _, key := range []string{"anyOf", "oneOf", "allOf", "not"} {
			if _, ok := node[key]; ok {
				return
			}
		}

		validation := map[string]any{}
		for _, key := range validationKeywords {
			if v, ok := node[key]; ok {
				validation[key] = v
				delete(node, key)
			}
		}
		if len(validation) == 0 {
			return
		}

		node["anyOf"] = []any{
			validation,
			map[string]any{"pattern": TemplatePattern},
		}
	})
	return mutations.MutationResult{Schema: schema}, nil
}
