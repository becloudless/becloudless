package probes

import (
	"fmt"
	"maps"
	"sort"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// probeNames are the fields of a container that hold a Probe.
var probeNames = map[string]bool{
	"livenessProbe":  true,
	"readinessProbe": true,
	"startupProbe":   true,
}

// Probes adds an "enabled" boolean to every container probe of the schema
// (livenessProbe, readinessProbe, startupProbe): `enabled: false` removes the
// probe, which is how a container opts out of a probe set by the defaults
// (`defaults.container`). The field is stripped from the rendered resource.
// The probes are reported via MutationResult.TemplateArgs (key "probePaths") so
// templates/mutations/_probes.tpl can apply it at render time.
type Probes struct{}

func (Probes) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	var paths []string
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if !isProbeNode(node, path) {
			return
		}
		props, _ := node["properties"].(map[string]any)
		merged := map[string]any{}
		maps.Copy(merged, props)
		merged["enabled"] = map[string]any{
			"type":        "boolean",
			"description": "Whether to set this probe. Defaults to true, false removes it (ex: a probe set by the defaults).",
		}
		node["properties"] = merged
		paths = append(paths, path)
	})

	sort.Strings(paths)
	quoted := make([]string, len(paths))
	for i, path := range paths {
		quoted[i] = fmt.Sprintf("%q", path)
	}

	return mutations.MutationResult{
		Schema:       schema,
		TemplateArgs: map[string]string{"probePaths": fmt.Sprintf("(list %s)", strings.Join(quoted, " "))},
	}, nil
}

// isProbeNode reports whether node is the schema of a Probe: an object found
// under a probe field, with the timing fields of a probe.
func isProbeNode(node map[string]any, path string) bool {
	name := path[strings.LastIndex(path, ".")+1:]
	if !probeNames[name] {
		return false
	}
	if !mutations.SchemaTypeIncludes(node["type"], "object") {
		return false
	}
	props, ok := node["properties"].(map[string]any)
	if !ok {
		return false
	}
	_, hasPeriod := props["periodSeconds"]
	return hasPeriod
}
