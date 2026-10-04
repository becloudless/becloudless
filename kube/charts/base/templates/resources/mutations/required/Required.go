package required

import (
	"fmt"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

type Required struct{}

func (Required) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	var required []string
	if req, ok := schema["required"].([]any); ok {
		for _, r := range req {
			if s, _ := r.(string); s != "" {
				required = append(required, s)
			}
		}
	}
	delete(schema, "required")
	result := mutations.MutationResult{Schema: schema}
	if len(required) > 0 {
		quoted := make([]string, len(required))
		for i, r := range required {
			quoted[i] = fmt.Sprintf("%q", r)
		}
		result.TemplateArgs = map[string]string{"required": fmt.Sprintf("(list %s)", strings.Join(quoted, " "))}
	}
	return result, nil
}
