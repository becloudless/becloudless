package main

import (
	"os"
	"strings"
)

// entry represents one resource kind declared in CRDs.yaml, e.g.:
//
//	configMaps:
//	  url: https://...configmap.json
//	  apiVersion: v1
//	  kind: ConfigMap
//	  contentIsSpec: false
type entry struct {
	name          string
	url           string
	apiVersion    string
	kind          string
	contentIsSpec bool     // defaults to true; set contentIsSpec: false in CRDs.yaml to override
	required      []string // top-level required fields, extracted from the upstream k8s schema by stripRequiredTransform
}

// parseCRDs is a minimal parser for the restricted YAML shape used by CRDs.yaml:
//
//	crds:
//	  <name>:
//	    url: <value>
//	    apiVersion: <value>
//	    kind: <value>
//	    contentIsSpec: <true|false>   # optional, defaults to true
//
// It avoids pulling in a YAML dependency for this single-purpose script.
func parseCRDs(path string) ([]entry, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var entries []entry
	var current *entry

	flush := func() {
		if current != nil {
			entries = append(entries, *current)
			current = nil
		}
	}

	for _, rawLine := range strings.Split(string(data), "\n") {
		line := strings.TrimRight(rawLine, " \t\r")
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}

		indent := len(line) - len(strings.TrimLeft(line, " "))
		trimmed := strings.TrimSpace(line)

		switch {
		case indent == 0:
			// top-level key, e.g. "crds:" — nothing to do.
			continue
		case indent == 2 && strings.HasSuffix(trimmed, ":"):
			flush()
			current = &entry{name: strings.TrimSuffix(trimmed, ":"), contentIsSpec: true}
		case indent == 4 && current != nil:
			key, value, ok := strings.Cut(trimmed, ":")
			if !ok {
				continue
			}
			value = strings.TrimSpace(value)
			switch strings.TrimSpace(key) {
			case "url":
				current.url = value
			case "apiVersion":
				current.apiVersion = value
			case "kind":
				current.kind = value
			case "contentIsSpec":
				current.contentIsSpec = value == "true"
			}
		}
	}
	flush()

	return entries, nil
}
