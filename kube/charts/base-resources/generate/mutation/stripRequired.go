package mutation

import (
	"fmt"
	"strings"
)

// StripRequired moves the schema's top-level "required" list (if any) out
// of the schema and into a "required" template arg (see
// Entry.AddTemplateArg), since .Values.resources.<name>.<id> and
// .Values.defaults.resources.<name> share this exact schema and a
// defaults.resources entry - a partial overlay - shouldn't be forced to
// satisfy "required" on its own. The extracted fields are instead enforced
// at render time on the merged resource (see the generate package's
// generateTemplate and templates/_requireFields.tpl).
func StripRequired(schema map[string]interface{}, e *Entry) (map[string]interface{}, error) {
	var required []string
	if req, ok := schema["required"].([]interface{}); ok {
		for _, r := range req {
			if s, _ := r.(string); s != "" {
				required = append(required, s)
			}
		}
	}
	delete(schema, "required")
	if len(required) > 0 {
		quoted := make([]string, len(required))
		for i, r := range required {
			quoted[i] = fmt.Sprintf("%q", r)
		}
		e.AddTemplateArg("required", fmt.Sprintf("(list %s)", strings.Join(quoted, " ")))
	}
	return schema, nil
}
