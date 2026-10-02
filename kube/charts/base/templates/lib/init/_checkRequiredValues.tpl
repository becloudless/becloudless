{{- define "base.lib.init.checkRequiredValues" }}
  {{- $rootContext := .rootContext }}

  {{- if $rootContext.Values.checkRequiredValues }}
    {{- $_ := set $rootContext "required" list }}
    {{- include "base.lib.init.checkRequiredValues.rec" (dict "rootContext" $rootContext "currentValue" $rootContext.Values "currentPath" "") }}
    {{- if $rootContext.required }}
      {{- $res := "" }}
      {{- range $i,$v := $rootContext.required }}
          {{- $res = printf "%s'%s' is required\n" $res $v }}
      {{- end }}
      {{- include "base.lib.utils.fail" (dict "rootContext" $rootContext
                                            "msg" (printf "\n\n%s" $res)) }}
    {{- end }}
  {{- end }}
{{- end }}

{{- define "base.lib.init.checkRequiredValues.rec" }}
  {{- $rootContext := .rootContext }}
  {{- $currentValue := .currentValue }}
  {{- $currentPath := .currentPath }}

  {{- if kindIs "invalid" $currentValue }}
    {{- $required := append $rootContext.required $currentPath }}
    {{- $_ := set $rootContext "required" $required }}
  {{- else if kindIs "map" $currentValue }}
    {{- range $key, $val := $currentValue }}
      {{- include "base.lib.init.checkRequiredValues.rec" (dict "rootContext" $rootContext "currentValue" $val "currentPath" (printf "%s.%s" $currentPath $key)) }}
    {{- end }}
  {{- else if kindIs "slice" $currentValue }}
    {{- range $i, $val := $currentValue }}
      {{- include "base.lib.init.checkRequiredValues.rec" (dict "rootContext" $rootContext "currentValue" $val "currentPath" (printf "%s[]" $currentPath)) }}
    {{- end }}
  {{- end }}
{{- end }}