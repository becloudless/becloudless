
{{/*
This function exists because merge() do not support not overwriting empty and false set values.
Yes it's using mergeOverride with reversed arguments to actually simulate a merge.
*/}}
{{- define "base.lib.utils.mergeInValuesNonOverwrite" -}}
  {{- $rootContext := .rootContext -}}
  {{- $obj := .obj -}}
  {{- $res := mergeOverwrite (deepCopy $obj) $rootContext.Values -}}
  {{- $_ := set .rootContext "Values" $res -}}
{{- end -}}
