{{/*
Merge library values into $.values. This function takes a list of libraries as dependencies from one to the other
*/}}
{{- define "base.lib.init.mergeLibrariesValuesIntoValues" -}}
  {{- $rootContext := .rootContext -}}
  {{- $libraryNames := .libraryNames -}}

  {{- $args := dict "currentValues" $rootContext.Values "libraryNames" $libraryNames "result" dict -}}
  {{- include "base.lib.init.mergeLibrariesValuesIntoPassedCurrentValues" $args -}}
  {{- $_ := set $rootContext "Values" $args.result -}}
{{- end -}}

{{/*
This function takes a values context and merge the passed library names values into the context.
This is done recursivly taking into account the order of library names in the list
*/}}
{{- define "base.lib.init.mergeLibrariesValuesIntoPassedCurrentValues" -}}
  {{- $currentValues := .currentValues -}}
  {{- $libraryNames := .libraryNames -}}

  {{- $firstLibraryName := first $libraryNames -}}
  {{- $innerLibNames := rest $libraryNames -}}
  {{- $firstLibraryValues := deepCopy (index $currentValues $firstLibraryName) -}}

  {{- if not (empty $innerLibNames) -}}
    {{- $args := (dict "currentValues" (index $currentValues $firstLibraryName) "libraryNames" $innerLibNames "result" dict) -}}
    {{- include "base.lib.init.mergeLibrariesValuesIntoPassedCurrentValues" $args -}}
    {{- $firstLibraryValues = $args.result -}}
  {{- end -}}

  {{- $currentValuesWithoutLibraryValues := omit $currentValues $firstLibraryName -}}
  {{- $mergedValues := mustMergeOverwrite $firstLibraryValues $currentValuesWithoutLibraryValues -}}
  {{- $_ := set . "result" $mergedValues -}}
{{- end -}}
