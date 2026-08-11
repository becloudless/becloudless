{{/*
Validate an enum value against acceptable values
*/}}
{{- define "base.lib.utils.failOnInvalidEnum" -}}
  {{- $enumName := .enumName -}}
  {{- $dict := .dict -}}
  {{- $validValues := .validValues -}}
  {{- $failIfEmpty := (default false .failIfEmpty) -}}

  {{- $enumValue := (get $dict $enumName) -}}
  {{- if (not $enumValue) -}}
    {{- fail (printf "Missing required property: `%s`. Valid values are %s" $enumName $validValues) -}}
  {{- end -}}
  {{- if or (and $failIfEmpty (empty $enumValue)) (not (has $enumValue $validValues)) -}}
    {{- fail (printf "Invalid property value: `%s` (%s). Valid values are %s" $enumName $enumValue $validValues) -}}
  {{- end -}}
{{- end -}}
