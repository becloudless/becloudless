package required

import (
	"fmt"
	"maps"
	"slices"
	"strings"

	"github.com/becloudless/becloudless/kube/charts/base/templates/resources/mutations"
)

// Required moves every "required" list of the schema, at any depth, out of the
// schema and into the helm template validation (see _required.tpl).
//
// A schema "required" is validated on the values before the defaults
// (defaults.resources.<kind>) are merged in a resource, so a field provided by
// the defaults would be reported missing, and the defaults themselves, which
// are partial by nature, would be rejected. The template validation runs on
// the resource once the defaults are merged.
//
// The required fields are reported via MutationResult.TemplateArgs (key
// "required") as a tree mirroring the structure of the values:
//
//	(dict
//	  "required" (list "scaleTargetRef")             fields required in this object
//	  "properties" (dict "spec" (dict ...))          the objects of its named properties
//	  "each" (dict ...))                             the objects of the entries of its map or list
//
// "each" is what the schema declares with additionalProperties and items. The
// arrays of objects are maps keyed by an id once ArraysToMaps has run, so it
// must run before this mutation, like EnvMaps and PortMaps, which reshape their
// nodes (PortMaps drops the "name" required of the ports, it is the map key).
//
// The "required" of a oneOf/anyOf branch is an alternative: it only applies if
// the value matches that branch, which the template validation cannot tell. It is
// left in the schema, only what the branches declare under their properties and
// items is validated.
type Required struct{}

type node struct {
	required   []string
	properties map[string]*node
	each       *node
}

func (n *node) empty() bool {
	return n == nil || (len(n.required) == 0 && len(n.properties) == 0 && n.each == nil)
}

func (n *node) merge(other *node) {
	if other.empty() {
		return
	}
	for _, r := range other.required {
		if !slices.Contains(n.required, r) {
			n.required = append(n.required, r)
		}
	}
	for name, child := range other.properties {
		if n.properties == nil {
			n.properties = map[string]*node{}
		}
		if existing, ok := n.properties[name]; ok {
			existing.merge(child)
		} else {
			n.properties[name] = child
		}
	}
	if other.each != nil {
		if n.each == nil {
			n.each = other.each
		} else {
			n.each.merge(other.each)
		}
	}
}

// expr renders the node as a template expression, "" when there is nothing to validate.
func (n *node) expr() string {
	if n.empty() {
		return ""
	}
	var parts []string
	if len(n.required) > 0 {
		required := slices.Sorted(slices.Values(n.required))
		quoted := make([]string, len(required))
		for i, r := range required {
			quoted[i] = fmt.Sprintf("%q", r)
		}
		parts = append(parts, fmt.Sprintf(`"required" (list %s)`, strings.Join(quoted, " ")))
	}
	if len(n.properties) > 0 {
		var props []string
		for _, name := range slices.Sorted(maps.Keys(n.properties)) {
			if expr := n.properties[name].expr(); expr != "" {
				props = append(props, fmt.Sprintf("%q %s", name, expr))
			}
		}
		if len(props) > 0 {
			parts = append(parts, fmt.Sprintf(`"properties" (dict %s)`, strings.Join(props, " ")))
		}
	}
	if n.each != nil {
		if expr := n.each.expr(); expr != "" {
			parts = append(parts, fmt.Sprintf(`"each" %s`, expr))
		}
	}
	return fmt.Sprintf("(dict %s)", strings.Join(parts, " "))
}

func (Required) Mutate(schema map[string]any) (mutations.MutationResult, error) {
	root := collect(schema, false)
	result := mutations.MutationResult{Schema: schema}
	if expr := root.expr(); expr != "" {
		result.TemplateArgs = map[string]string{"required": expr}
	}
	return result, nil
}

// collect deletes the "required" lists found at and under schema, and returns
// them as a tree. alternative is true for a oneOf/anyOf branch, whose own
// "required" is kept.
func collect(schema map[string]any, alternative bool) *node {
	out := &node{}
	if !alternative {
		if req, ok := schema["required"].([]any); ok {
			for _, r := range req {
				if s, _ := r.(string); s != "" && !slices.Contains(out.required, s) {
					out.required = append(out.required, s)
				}
			}
			delete(schema, "required")
		}
	}

	if props, ok := schema["properties"].(map[string]any); ok {
		for name, v := range props {
			child, ok := v.(map[string]any)
			if !ok {
				continue
			}
			if c := collect(child, false); !c.empty() {
				if out.properties == nil {
					out.properties = map[string]*node{}
				}
				out.properties[name] = c
			}
		}
	}
	for _, key := range []string{"additionalProperties", "items"} {
		child, ok := schema[key].(map[string]any)
		if !ok {
			continue
		}
		if c := collect(child, false); !c.empty() {
			if out.each == nil {
				out.each = &node{}
			}
			out.each.merge(c)
		}
	}
	for _, key := range []string{"oneOf", "anyOf", "allOf"} {
		branches, ok := schema[key].([]any)
		if !ok {
			continue
		}
		for _, b := range branches {
			branch, ok := b.(map[string]any)
			if !ok {
				continue
			}
			out.merge(collect(branch, key != "allOf"))
		}
	}
	return out
}
