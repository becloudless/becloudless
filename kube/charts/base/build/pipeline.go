package build

import (
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/additionalPropertiesFalse"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/arraysToMaps"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/content"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/enabled"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/envMaps"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/flattenAllOf"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/metadata"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/normalizeIntOrString"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/portMaps"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/required"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/stringifyFields"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/templatedStrings"
)

// Pipeline returns the ordered list of schema mutations applied to every
// resource's instance schema (see fetchAndMutateSchema).
func Pipeline(extractContent content.ExtractContent, arrays *arraysToMaps.ArraysToMaps, stringify *stringifyFields.StringifyFields) []mutations.Mutation {
	if arrays == nil {
		arrays = &arraysToMaps.ArraysToMaps{}
	}
	if stringify == nil {
		stringify = &stringifyFields.StringifyFields{}
	}
	return []mutations.Mutation{
		extractContent,
		flattenAllOf.FlattenAllOf{},
		normalizeIntOrString.NormalizeIntOrString{},
		metadata.Metadata{},
		enabled.Enabled{},
		envMaps.EnvMaps{},   // before arraysToMaps, which would otherwise convert env to an id-keyed map
		portMaps.PortMaps{}, // before arraysToMaps, same reason as envMaps
		*arrays,
		required.Required{}, // after the mutations reshaping the nodes (env, ports and arrays), it moves the nested required out of the schema
		*stringify,
		templatedStrings.TemplatedStrings{}, // last of the schema relaxations: wraps the validation the other mutations left on the strings
		additionalPropertiesFalse.AdditionalPropertiesFalse{},
	}
}
