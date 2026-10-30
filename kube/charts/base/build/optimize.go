package build

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"
)

// dedupeMinSize is the size in bytes under which a repeated subschema is left in place: the reference that replaces it is
// not much smaller.
const dedupeMinSize = 300

// schemaDoc is a named schema, the subschemas are shared between the documents.
type schemaDoc struct {
	name string
	root map[string]any
}

// refLocation gives the value of the `$ref` that, from a document, points to the node of another document at the JSON
// pointer made of the tokens.
type refLocation func(from, to string, tokens []string) string

// optimizeSchemas makes the schemas smaller without changing what they validate: it drops the `x-kubernetes-*` extensions, and
// replaces every subschema found several times (across all the documents) by a `$ref` to its first occurrence, which stays in
// place. The `description` is not part of the comparison and stays next to the `$ref`.
//
// The documents are walked in order, so the first occurrence is the one of the first document: put first the document that
// other schemas point into. The `$ref` do not follow JSON pointers, the pointers must not traverse a replaced node: they are
// checked, the pointers are relative to the root of the document named like the key.
func optimizeSchemas(docs []schemaDoc, location refLocation, pointers map[string][]string) error {
	for _, d := range docs {
		stripExtensions(d.root)
	}

	d := &deduper{
		location: location,
		hasher:   &hasher{memo: map[uintptr]*nodeInfo{}},
		count:    map[string]int{},
		first:    map[string]nodeLocation{},
	}
	for _, doc := range docs {
		d.countNode(doc.root, true)
	}
	for _, doc := range docs {
		d.replace(doc.name, doc.root, nil)
	}

	for _, doc := range docs {
		for _, pointer := range pointers[doc.name] {
			if err := checkPointer(doc.root, pointer); err != nil {
				return fmt.Errorf("%s: %w", doc.name, err)
			}
		}
	}
	return nil
}

// checkPointer fails when the pointer traverses a `$ref`.
func checkPointer(root map[string]any, pointer string) error {
	var node any = root
	for _, token := range strings.Split(strings.TrimPrefix(pointer, "/"), "/") {
		m, ok := node.(map[string]any)
		if !ok {
			return fmt.Errorf("pointer %q: %q is not an object", pointer, token)
		}
		if _, ref := m["$ref"]; ref {
			return fmt.Errorf("pointer %q goes through a $ref before %q", pointer, token)
		}
		node = m[token]
	}
	if node == nil {
		return fmt.Errorf("pointer %q does not exist", pointer)
	}
	return nil
}

// orderDocs puts the document with the given names first, the others keep their order.
func orderDocs(docs []schemaDoc, first ...string) []schemaDoc {
	out := make([]schemaDoc, 0, len(docs))
	for _, name := range first {
		for _, d := range docs {
			if d.name == name {
				out = append(out, d)
			}
		}
	}
	for _, d := range docs {
		if !contains(first, d.name) {
			out = append(out, d)
		}
	}
	return out
}

func contains(list []string, s string) bool {
	for _, item := range list {
		if item == s {
			return true
		}
	}
	return false
}

// optimizeResourceFiles optimizes the schema of every resource file of the directory, the files point to each other.
func optimizeResourceFiles(dir string, entries []resource) error {
	schemaDir := filepath.Join(dir, "schema", "resources")

	docs := make([]schemaDoc, 0, len(entries))
	for _, e := range entries {
		data, err := os.ReadFile(filepath.Join(schemaDir, e.Name+".json"))
		if err != nil {
			return fmt.Errorf("read %s.json: %w", e.Name, err)
		}
		var root map[string]any
		if err := json.Unmarshal(data, &root); err != nil {
			return fmt.Errorf("parse %s.json: %w", e.Name, err)
		}
		docs = append(docs, schemaDoc{name: e.Name, root: root})
	}
	docs = orderDocs(docs, "deployments")

	location := func(from, to string, tokens []string) string {
		if from == to {
			return "#" + pointerOf(tokens)
		}
		return "./" + to + ".json#" + pointerOf(tokens)
	}
	if err := optimizeSchemas(docs, location, workloadPointers()); err != nil {
		return err
	}

	for _, d := range docs {
		out, err := json.MarshalIndent(d.root, "", "  ")
		if err != nil {
			return fmt.Errorf("marshal %s.json: %w", d.name, err)
		}
		if err := os.WriteFile(filepath.Join(schemaDir, d.name+".json"), append(out, '\n'), 0o644); err != nil {
			return err
		}
	}
	return nil
}

// workloadPointers are the pointers into the schema of the deployments that the defaults of the pod and of the container
// reference.
func workloadPointers() map[string][]string {
	return map[string][]string{"deployments": {podSchemaPointer, containerSchemaPointer}}
}

func pointerOf(tokens []string) string {
	var sb strings.Builder
	for _, t := range tokens {
		t = strings.ReplaceAll(strings.ReplaceAll(t, "~", "~0"), "/", "~1")
		sb.WriteString("/" + url.PathEscape(t))
	}
	return sb.String()
}

type nodeLocation struct {
	doc    string
	tokens []string
}

type deduper struct {
	location refLocation
	hasher   *hasher
	count    map[string]int
	first    map[string]nodeLocation
}

func (d *deduper) eligible(i *nodeInfo) bool {
	return i.size >= dedupeMinSize
}

// countNode counts the occurrences of the subschemas. A repeated subschema is not entered again: its content stays in its
// first occurrence only.
func (d *deduper) countNode(node map[string]any, root bool) {
	i := d.hasher.info(node)
	if !root && d.eligible(i) {
		d.count[i.body]++
		if d.count[i.body] > 1 {
			return
		}
	}
	for _, s := range schemaSlots(node) {
		d.countNode(s.node, false)
	}
}

// replace walks the nodes in the order of countNode, and replaces the repeated subschemas other than the first one.
func (d *deduper) replace(doc string, node map[string]any, tokens []string) {
	for _, s := range schemaSlots(node) {
		i := d.hasher.info(s.node)
		at := append(append([]string{}, tokens...), s.tokens...)
		if d.eligible(i) && d.count[i.body] > 1 {
			if first, ok := d.first[i.body]; ok {
				ref := map[string]any{"$ref": d.location(doc, first.doc, first.tokens)}
				if description, ok := s.node["description"]; ok {
					ref["description"] = description
				}
				s.set(ref)
				continue
			}
			d.first[i.body] = nodeLocation{doc: doc, tokens: at}
		}
		d.replace(doc, s.node, at)
	}
}

// nodeInfo describes a subschema: body hashes it without its own description, full hashes it with.
type nodeInfo struct {
	node map[string]any // kept to keep the address of the node unique
	body string
	full string
	size int
}

type hasher struct {
	memo map[uintptr]*nodeInfo
}

func (h *hasher) info(node map[string]any) *nodeInfo {
	address := reflect.ValueOf(node).Pointer()
	if i, ok := h.memo[address]; ok {
		return i
	}

	slots := map[string][]slot{}
	for _, s := range schemaSlots(node) {
		slots[s.tokens[0]] = append(slots[s.tokens[0]], s)
	}

	body := sha256.New()
	size := 0
	for _, key := range sortedKeys(node) {
		if key == "description" {
			continue
		}
		_, _ = io.WriteString(body, key+"\x00")
		size += len(key) + 4
		if children, ok := slots[key]; ok {
			for _, s := range children {
				child := h.info(s.node)
				name := strings.Join(s.tokens[1:], "/")
				_, _ = io.WriteString(body, name+"\x00"+child.full+"\x00")
				size += len(name) + child.size
			}
			continue
		}
		raw, _ := json.Marshal(node[key])
		_, _ = body.Write(raw)
		size += len(raw)
	}

	bodySum := hex.EncodeToString(body.Sum(nil))
	description, _ := json.Marshal(node["description"])
	fullSum := sha256.Sum256([]byte(bodySum + string(description)))
	i := &nodeInfo{node: node, body: bodySum, full: hex.EncodeToString(fullSum[:]), size: size + len(description)}
	h.memo[address] = i
	return i
}

// slot is a subschema and the way to replace it in its parent. The tokens are the JSON pointer from the parent.
type slot struct {
	tokens []string
	node   map[string]any
	set    func(any)
}

// schemaSlots lists the subschemas of a schema, in a stable order. Only the keywords that hold schemas are followed, not the
// `default`, `enum` and the like.
func schemaSlots(node map[string]any) []slot {
	var out []slot
	for _, key := range sortedKeys(node) {
		key := key
		switch key {
		case "properties", "patternProperties", "$defs", "definitions":
			m, ok := node[key].(map[string]any)
			if !ok {
				continue
			}
			for _, name := range sortedKeys(m) {
				name := name
				if child, ok := m[name].(map[string]any); ok {
					out = append(out, slot{tokens: []string{key, name}, node: child, set: func(v any) { m[name] = v }})
				}
			}
		case "additionalProperties", "additionalItems", "not", "if", "then", "else", "contains", "propertyNames", "items":
			switch v := node[key].(type) {
			case map[string]any:
				out = append(out, slot{tokens: []string{key}, node: v, set: func(x any) { node[key] = x }})
			case []any:
				out = append(out, listSlots(key, v)...)
			}
		case "anyOf", "oneOf", "allOf":
			if list, ok := node[key].([]any); ok {
				out = append(out, listSlots(key, list)...)
			}
		}
	}
	return out
}

func listSlots(key string, list []any) []slot {
	var out []slot
	for index := range list {
		index := index
		if child, ok := list[index].(map[string]any); ok {
			out = append(out, slot{tokens: []string{key, strconv.Itoa(index)}, node: child, set: func(v any) { list[index] = v }})
		}
	}
	return out
}

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// stripExtensions removes the `x-kubernetes-*` keywords, no validator uses them.
func stripExtensions(node map[string]any) {
	for key := range node {
		if strings.HasPrefix(key, "x-kubernetes-") {
			delete(node, key)
		}
	}
	for _, s := range schemaSlots(node) {
		stripExtensions(s.node)
	}
}
