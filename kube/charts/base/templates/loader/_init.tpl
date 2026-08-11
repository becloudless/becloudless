{{- define "base.loader.init" -}}
  {{- include "base.lib.init.mergeLibrariesValuesIntoValues" (dict "rootContext" $ "libraryNames" (list "base")) }}

  {{- /* Check required values. Run after values merge to check the feature is enabled, but before features preparation, to validate only what the user set */ -}}
  {{- include "base.lib.init.checkRequiredValues" . }}

  {{- /* Apply all features */ -}}
  {{- include "base.features" . }}

  {{- /* feature are run 2 times to let feature depend on resources setup and having the same behavior than on downstream features charts */ -}}
  {{- include "base.features" . }}

{{- end -}}
