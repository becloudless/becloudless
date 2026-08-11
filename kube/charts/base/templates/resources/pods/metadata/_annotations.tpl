{{- /*
Returns the value for annotations
*/ -}}
{{- define "base.resources.pods.metadata.annotations" -}}
  {{- $rootContext := .rootContext -}}
  {{- $controllerObject := .controllerObject -}}

  {{- /* Default annotations */ -}}
  {{- $annotations := dict -}}

  {{- /* See if a pod-specific override is set */ -}}
  {{- if hasKey $controllerObject "pod" -}}
    {{- $podOption := get $controllerObject.pod "annotations" -}}
    {{- if not (empty $podOption) -}}
      {{- $annotations = merge $podOption $annotations -}}
    {{- end -}}
  {{- end -}}

  {{- /* Add configMaps checksum */ -}}
  {{- $configMapsFound := dict -}}
  {{- range $name, $configmap := $rootContext.Values.resources.configMaps -}}
    {{- if include "base.lib.utils.isEnabled" $configmap -}}
      {{- $_ := set $configMapsFound $name (toYaml $configmap.data | sha256sum) -}}
    {{- end -}}
  {{- end -}}
  {{- if $configMapsFound -}}
    {{- $annotations = merge
      (dict "checksum/configMaps" (toYaml $configMapsFound | sha256sum))
      $annotations
    -}}
  {{- end -}}

  {{- /* Add SealedSecrets checksum */ -}}
  {{- $sealedSecretsFound := dict -}}
  {{- range $name, $secret := $rootContext.Values.resources.sealedSecrets -}}
    {{- if include "base.lib.utils.isEnabled" $secret -}}
      {{- $_ := set $sealedSecretsFound $name (toYaml $secret.encryptedData | sha256sum) -}}
    {{- end -}}
  {{- end -}}
  {{- if $sealedSecretsFound -}}
    {{- $annotations = merge
      (dict "checksum/sealedSecrets" (toYaml $sealedSecretsFound | sha256sum))
      $annotations
    -}}
  {{- end -}}

  {{- /* Add secrets checksum */ -}}
  {{- $secretsFound := dict -}}
  {{- range $name, $secret := $rootContext.Values.resources.secrets -}}
    {{- if include "base.lib.utils.isEnabled" $secret -}}
      {{- $_ := set $secretsFound $name (toYaml $secret.encryptedData | sha256sum) -}}
    {{- end -}}
  {{- end -}}
  {{- if $secretsFound -}}
    {{- $annotations = merge
      (dict "checksum/secrets" (toYaml $secretsFound | sha256sum))
      $annotations
    -}}
  {{- end -}}

  {{- if not (empty $annotations) -}}
    {{- $annotations | toYaml -}}
  {{- end -}}
{{- end -}}
