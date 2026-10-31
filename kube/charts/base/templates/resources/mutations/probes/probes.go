package probes

import (
	"fmt"
	"maps"
	"slices"
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

// handlerNames are the fields of a Probe that hold what the probe does, and portHandlerNames the ones that have a port.
var (
	handlerNames     = []string{"exec", "grpc", "httpGet", "tcpSocket"}
	portHandlerNames = []string{"grpc", "httpGet", "tcpSocket"}
)

const (
	portNote = "Defaults to the only port of the container, or to its port named `http`."

	sharedProbeDescription = "The handler (`httpGet`, `tcpSocket`, `grpc` or `exec`) of the livenessProbe, readinessProbe and startupProbe that set none. The timings stay the ones of `defaults.container` and of each probe."
)

// Probes adds an "enabled" boolean to every container probe of the schema
// (livenessProbe, readinessProbe, startupProbe): `enabled: false` removes the
// probe, which is how a container opts out of a probe set by the defaults
// (`defaults.container`). The field is stripped from the rendered resource.
//
// The `port` of the handlers is optional: it defaults to the port of the container, the only one it has or the one named
// `http`. The containers get a `probe` field, the handler shared by their probes that have none
// (`probe: {httpGet: {path: /health}}`), also stripped from the rendered resource.
//
// The probes are reported via MutationResult.TemplateArgs (key "probePaths") so
// templates/mutations/_probes.tpl can apply it at render time.
type Probes struct{}

func (Probes) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	var paths []string
	var handlers map[string]any // the schema of the handlers, from the first probe found
	mutations.WalkSchemaNodesWithPath(schema, "", func(node map[string]any, path string) {
		if !isProbeNode(node, path) {
			// the probes are visited before the container that holds them
			if handlers != nil {
				addSharedProbe(node, handlers)
			}
			return
		}
		props, _ := node["properties"].(map[string]any)
		makePortOptional(props)
		if handlers == nil {
			handlers = handlerSchemas(props)
		}
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

// makePortOptional removes `port` from the required fields of the handlers of a probe, and says what it defaults to.
func makePortOptional(probeProps map[string]any) {
	for _, name := range portHandlerNames {
		handler, ok := probeProps[name].(map[string]any)
		if !ok {
			continue
		}
		if required, ok := handler["required"].([]any); ok {
			handler["required"] = slices.DeleteFunc(required, func(r any) bool { return r == "port" })
			if len(handler["required"].([]any)) == 0 {
				delete(handler, "required")
			}
		}
		handlerProps, _ := handler["properties"].(map[string]any)
		if port, ok := handlerProps["port"].(map[string]any); ok {
			description, _ := port["description"].(string)
			port["description"] = strings.TrimSpace(description + "\n" + portNote)
		}
	}
}

// handlerSchemas returns a copy of the schemas of the handlers of a probe.
func handlerSchemas(probeProps map[string]any) map[string]any {
	out := map[string]any{}
	for _, name := range handlerNames {
		if handler, ok := probeProps[name]; ok {
			out[name] = mutations.DeepCopy(handler)
		}
	}
	return out
}

// addSharedProbe adds the `probe` field to a container: the node holds probes, which have already got their `enabled` field.
func addSharedProbe(node map[string]any, handlers map[string]any) {
	props, ok := node["properties"].(map[string]any)
	if !ok {
		return
	}
	if _, exists := props["probe"]; exists {
		return
	}
	for name := range probeNames {
		probe, _ := props[name].(map[string]any)
		probeProps, _ := probe["properties"].(map[string]any)
		if _, hasEnabled := probeProps["enabled"]; hasEnabled {
			props["probe"] = map[string]any{
				"type":        "object",
				"description": sharedProbeDescription,
				"properties":  mutations.DeepCopy(handlers),
			}
			return
		}
	}
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
