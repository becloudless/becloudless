package portMaps

import (
	"fmt"
	"slices"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// PortMaps converts every "ports" array of the schema holding named ports
// (Service ServicePort: "name" + "port", container ContainerPort: "name" +
// "containerPort") into a map where the KEY is the port name and the VALUE is
// the port object without its "name":
//
//	ports:
//	  http:
//	    port: 80
//	    targetPort: http
//	  ldaps:
//	    port: 636
//
// Other "ports" arrays (ex: NetworkPolicy ports, which have no name) are left
// to ArraysToMaps. It must run BEFORE ArraysToMaps, which would otherwise turn
// the same node into an id-keyed map of full port objects. Converted schema
// paths are reported via MutationResult.TemplateArgs (key "portPaths") so
// templates/resources/mutations/portMaps/_mapsToPorts.tpl can reverse the
// conversion at render time.
type PortMaps struct{}

func (m PortMaps) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	var convertedPaths []string
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if path != "ports" && !strings.HasSuffix(path, ".ports") {
			return
		}
		if convertPortNodeToMap(node) {
			convertedPaths = append(convertedPaths, path)
		}
	})

	sort.Strings(convertedPaths)
	quoted := make([]string, len(convertedPaths))
	for i, path := range convertedPaths {
		quoted[i] = fmt.Sprintf("%q", path)
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: map[string]string{"portPaths": fmt.Sprintf("(list %s)", strings.Join(quoted, " "))},
	}, nil
}

func convertPortNodeToMap(node map[string]any) bool {
	if !mutations.SchemaTypeIncludes(node["type"], "array") {
		return false
	}
	items, ok := node["items"].(map[string]any)
	if !ok {
		return false
	}
	props, ok := items["properties"].(map[string]any)
	if !ok {
		return false
	}
	_, hasName := props["name"]
	_, hasPort := props["port"]
	_, hasContainerPort := props["containerPort"]
	if !hasName || (!hasPort && !hasContainerPort) {
		return false
	}

	// the name is now the map key
	delete(props, "name")
	if required, ok := items["required"].([]any); ok {
		items["required"] = slices.DeleteFunc(required, func(r any) bool { return r == "name" })
	}

	node["type"] = mutations.ReplaceSchemaType(node["type"], "array", "object")
	node["additionalProperties"] = items
	delete(node, "items")
	delete(node, "minItems")
	delete(node, "maxItems")
	delete(node, "uniqueItems")
	delete(node, "x-kubernetes-list-type")
	delete(node, "x-kubernetes-list-map-keys")
	return true
}
