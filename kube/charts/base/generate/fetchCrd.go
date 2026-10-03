package generate

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"strings"

	"gopkg.in/yaml.v3"
)

func fetchCRDManifestSchema(client *http.Client, url, crdVersion, kindHint string) (schema map[string]any, apiVersion string, kind string, err error) {
	resp, err := client.Get(url)
	if err != nil {
		return nil, "", "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, "", "", fmt.Errorf("unexpected status %s", resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", "", err
	}

	type match struct {
		group, kind string
		schema      map[string]any
	}
	var matches []match

	decoder := yaml.NewDecoder(bytes.NewReader(body))
	for {
		var manifest map[string]any
		if err := decoder.Decode(&manifest); err != nil {
			if err == io.EOF {
				break
			}
			return nil, "", "", fmt.Errorf("parse CRD manifest: %w", err)
		}

		spec, _ := manifest["spec"].(map[string]any)
		group, _ := spec["group"].(string)
		names, _ := spec["names"].(map[string]any)
		manifestKind, _ := names["kind"].(string)
		if group == "" || manifestKind == "" {
			continue
		}
		if kindHint != "" && manifestKind != kindHint {
			continue
		}

		versions, _ := spec["versions"].([]any)
		for _, v := range versions {
			version, ok := v.(map[string]any)
			if !ok {
				continue
			}
			name, _ := version["name"].(string)
			if name != crdVersion {
				continue
			}
			versionSchema, _ := version["schema"].(map[string]any)
			openAPISchema, _ := versionSchema["openAPIV3Schema"].(map[string]any)
			if openAPISchema == nil {
				return nil, "", "", fmt.Errorf("CRD manifest %s: version %q has no spec.schema.openAPIV3Schema", url, crdVersion)
			}
			matches = append(matches, match{group: group, kind: manifestKind, schema: openAPISchema})
		}
	}

	switch len(matches) {
	case 0:
		if kindHint != "" {
			return nil, "", "", fmt.Errorf("CRD manifest %s: no document with kind %q and version %q found", url, kindHint, crdVersion)
		}
		return nil, "", "", fmt.Errorf("CRD manifest %s: no document with version %q found", url, crdVersion)
	case 1:
		return matches[0].schema, matches[0].group + "/" + crdVersion, matches[0].kind, nil
	default:
		kinds := make([]string, len(matches))
		for i, m := range matches {
			kinds[i] = m.kind
		}
		return nil, "", "", fmt.Errorf("CRD manifest %s: multiple kinds found for version %q (%s), set sourceCRD.kind to disambiguate", url, crdVersion, strings.Join(kinds, ", "))
	}
}
