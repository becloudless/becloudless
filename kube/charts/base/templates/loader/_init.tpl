{{- define "base.loader.init" }}
  {{- include "base.lib.init.mergeLibrariesValuesIntoValues" (dict "rootContext" $ "libraryNames" (list "base")) }}

  {{- /* Check required values. Run after values merge to check the feature is enabled, but before features preparation, to validate only what the user set */}}
  {{- include "base.lib.init.checkRequiredValues" $ }}

{{- end }}
