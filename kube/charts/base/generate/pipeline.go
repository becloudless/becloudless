package generate

import (
	"resourceschart/templates/resources/mutations"
	"resourceschart/templates/resources/mutations/additionalPropertiesFalse"
	"resourceschart/templates/resources/mutations/arraysToMaps"
	"resourceschart/templates/resources/mutations/content"
	"resourceschart/templates/resources/mutations/enabled"
	"resourceschart/templates/resources/mutations/flattenAllOf"
	"resourceschart/templates/resources/mutations/metadata"
	"resourceschart/templates/resources/mutations/normalizeIntOrString"
	"resourceschart/templates/resources/mutations/required"
	"resourceschart/templates/resources/mutations/stringifyFields"
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
