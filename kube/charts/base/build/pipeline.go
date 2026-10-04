package build

import (
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/additionalPropertiesFalse"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/arraysToMaps"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/content"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/enabled"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/flattenAllOf"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/metadata"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/normalizeIntOrString"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/required"
	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations/stringifyFields"
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
		required.Required{},
		metadata.Metadata{},
		enabled.Enabled{},
		*arrays,
		*stringify,
		additionalPropertiesFalse.AdditionalPropertiesFalse{},
	}
}
