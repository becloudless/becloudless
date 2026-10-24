{{- /*
Rolls the pods out when a ConfigMap or a Secret they use changes: adds the annotations `checksum/configmaps` and `checksum/secrets` to
the pod template of the Deployments, StatefulSets and DaemonSets, so a change of the content is a change of the pod template.

Only the ConfigMaps and Secrets defined by the same release (`resources.configMaps` and `resources.secrets`) are known: their content is
hashed (`data`, `binaryData` and `stringData`) for each one that the pod uses, as an `env` or `envFrom` reference, a `configMap` or `secret`
volume, or a projected volume source. The ones that are made elsewhere (generated, external or cert-manager secrets, ConfigMaps of
another release) are not visible at render time and are ignored.

The annotations set on the pod template by the resource are kept.
*/}}
{{- define "base.resources.mutations.checksums" }}
  {{- $work := .work }}
  {{- if and $work.enabled (has (.kind | default "") (list "Deployment" "StatefulSet" "DaemonSet")) }}
    {{- $rootContext := .rootContext }}
    {{- $resourcesAll := $rootContext.Values.resources | default dict }}
    {{- $object := $work.object | default dict }}
    {{- $spec := $object.spec | default dict }}
    {{- $podTemplate := $spec.template | default dict }}
    {{- $podSpec := $podTemplate.spec | default dict }}

    {{- /* the names of the ConfigMaps and the Secrets used by the pod */}}
    {{- $usedConfigMaps := dict }}
    {{- $usedSecrets := dict }}
    {{- range $containers := (list ($podSpec.containers | default list) ($podSpec.initContainers | default list)) }}
      {{- range $container := $containers }}
        {{- range $env := ($container.env | default list) }}
          {{- $valueFrom := $env.valueFrom | default dict }}
          {{- $ref := $valueFrom.configMapKeyRef | default dict }}
          {{- if $ref.name }}{{- $_ := set $usedConfigMaps $ref.name true }}{{- end }}
          {{- $ref = $valueFrom.secretKeyRef | default dict }}
          {{- if $ref.name }}{{- $_ := set $usedSecrets $ref.name true }}{{- end }}
        {{- end }}
        {{- range $envFrom := ($container.envFrom | default list) }}
          {{- $ref := $envFrom.configMapRef | default dict }}
          {{- if $ref.name }}{{- $_ := set $usedConfigMaps $ref.name true }}{{- end }}
          {{- $ref = $envFrom.secretRef | default dict }}
          {{- if $ref.name }}{{- $_ := set $usedSecrets $ref.name true }}{{- end }}
        {{- end }}
      {{- end }}
    {{- end }}
    {{- range $volume := ($podSpec.volumes | default list) }}
      {{- $ref := $volume.configMap | default dict }}
      {{- if $ref.name }}{{- $_ := set $usedConfigMaps $ref.name true }}{{- end }}
      {{- $ref = $volume.secret | default dict }}
      {{- if $ref.secretName }}{{- $_ := set $usedSecrets $ref.secretName true }}{{- end }}
      {{- range $source := (($volume.projected | default dict).sources | default list) }}
        {{- $ref = $source.configMap | default dict }}
        {{- if $ref.name }}{{- $_ := set $usedConfigMaps $ref.name true }}{{- end }}
        {{- $ref = $source.secret | default dict }}
        {{- if $ref.name }}{{- $_ := set $usedSecrets $ref.name true }}{{- end }}
      {{- end }}
    {{- end }}

    {{- /* `<name>:<hash of the content>` for the ones the release defines, sorted by name */}}
    {{- $configMapSums := list }}
    {{- range $id, $resource := ($resourcesAll.configMaps | default dict) }}
      {{- $resource = $resource | default dict }}
      {{- $name := include "base.lib.computeResourceName" (dict "rootContext" $rootContext "id" $id "resource" $resource) }}
      {{- if hasKey $usedConfigMaps $name }}
        {{- $sum := dict "data" $resource.data "binaryData" $resource.binaryData | toJson | sha256sum }}
        {{- $configMapSums = append $configMapSums (printf "%s:%s" $name $sum) }}
      {{- end }}
    {{- end }}
    {{- $secretSums := list }}
    {{- range $id, $resource := ($resourcesAll.secrets | default dict) }}
      {{- $resource = $resource | default dict }}
      {{- $name := include "base.lib.computeResourceName" (dict "rootContext" $rootContext "id" $id "resource" $resource) }}
      {{- if hasKey $usedSecrets $name }}
        {{- $sum := dict "data" $resource.data "stringData" $resource.stringData | toJson | sha256sum }}
        {{- $secretSums = append $secretSums (printf "%s:%s" $name $sum) }}
      {{- end }}
    {{- end }}

    {{- $checksums := dict }}
    {{- if $configMapSums }}
      {{- $_ := set $checksums "checksum/configmaps" (sortAlpha $configMapSums | join "," | sha256sum) }}
    {{- end }}
    {{- if $secretSums }}
      {{- $_ := set $checksums "checksum/secrets" (sortAlpha $secretSums | join "," | sha256sum) }}
    {{- end }}

    {{- if $checksums }}
      {{- $metadata := $podTemplate.metadata | default dict }}
      {{- $annotations := merge (dict) ($metadata.annotations | default dict) $checksums }}
      {{- $metadata = set $metadata "annotations" $annotations }}
      {{- $podTemplate = set $podTemplate "metadata" $metadata }}
      {{- $spec = set $spec "template" $podTemplate }}
      {{- $object = set $object "spec" $spec }}
      {{- $work = set $work "object" $object }}
    {{- end }}
  {{- end }}
  {{- toYaml $work }}
{{- end }}
