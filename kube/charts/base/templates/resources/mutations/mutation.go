package mutations

import "maps"

type MutationResult struct {
	Schema       map[string]any
	TemplateArgs map[string]string
}

type Mutation interface {
	Mutate(schema map[string]any) (MutationResult, error)
}

func MutateSchema(mutations []Mutation, schema map[string]any) (MutationResult, error) {
	templateArgs := map[string]string{}
	for _, m := range mutations {
		result, err := m.Mutate(schema)
		if err != nil {
			return MutationResult{}, err
		}
		schema = result.Schema
		maps.Copy(templateArgs, result.TemplateArgs)
	}
	return MutationResult{Schema: schema, TemplateArgs: templateArgs}, nil
}
