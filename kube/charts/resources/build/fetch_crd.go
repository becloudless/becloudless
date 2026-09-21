package main

import (
	"bytes"
	"fmt"
	"io"
	"net/http"

	"gopkg.in/yaml.v3"
)

// fetchCRDManifestSchema fetches a CustomResourceDefinition manifest (YAML,
// possibly containing multiple "---"-separated documents, e.g. longhorn's
// bundled crds.yaml) from url and extracts the OpenAPI v3 schema declared
// for the given CRD version, i.e.:
//
//	spec:
//	  names:
//	    kind: <kind>
//	  versions:
//	    - name: <crdVersion>
//	      schema:
//	        openAPIV3Schema: { ... }  # this is what's returned
//
// When the manifest contains multiple documents, only the document whose
// spec.names.kind matches kind is considered, so that fetching a bundled
// multi-CRD file for one kind doesn't accidentally return another kind's
// schema just because it also happens to declare a version named
// crdVersion.
//
// This lets resources.yaml reference third-party CRDs (e.g. bitnami's
// SealedSecret, or flux's HelmRelease/Kustomization) whose schema is only
// published as part of their own CRD manifest, rather than as a standalone
// JSON schema file like the built-in k8s kinds fetched from
// kubernetes-json-schema.
func fetchCRDManifestSchema(client *http.Client, url, crdVersion, kind string) (map[string]interface{}, error) {
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %s", resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	decoder := yaml.NewDecoder(bytes.NewReader(body))
	for {
		var manifest map[string]interface{}
		if err := decoder.Decode(&manifest); err != nil {
			if err == io.EOF {
				break
			}
			return nil, fmt.Errorf("parse CRD manifest: %w", err)
		}

		spec, _ := manifest["spec"].(map[string]interface{})
		if kind != "" {
			names, _ := spec["names"].(map[string]interface{})
			manifestKind, _ := names["kind"].(string)
			if manifestKind != kind {
				continue
			}
		}
		versions, _ := spec["versions"].([]interface{})
		for _, v := range versions {
			version, ok := v.(map[string]interface{})
			if !ok {
				continue
			}
			name, _ := version["name"].(string)
			if name != crdVersion {
				continue
			}
			schema, _ := version["schema"].(map[string]interface{})
			openAPISchema, _ := schema["openAPIV3Schema"].(map[string]interface{})
			if openAPISchema == nil {
				return nil, fmt.Errorf("CRD manifest %s: version %q has no spec.schema.openAPIV3Schema", url, crdVersion)
			}
			return openAPISchema, nil
		}
	}

	return nil, fmt.Errorf("CRD manifest %s: no document with kind %q and version %q found", url, kind, crdVersion)
}
