{{/*
Convert kafkaUsers values to an object
*/}}
{{- define "base.resources.kafkaUsers.valuesToObject" -}}
  {{- $rootContext := .rootContext -}}
  {{- $identifier := .id -}}
  {{- $objectValues := .values -}}

  {{- include "base.lib.resource.defaultValuesToObject" . -}}

  {{- /* Identify the Kafka cluster's full name and namespace. */ -}}
  {{- $clusterInfo :=
        (
          (include "base.resources.kafkaUsers.lib.clusterProperties" $objectValues.kafkaCluster)
          | fromYaml
        )
  }}
  {{- if (not (empty $clusterInfo)) }}
    {{- $_ := set $objectValues "namespace"
          (get $clusterInfo "namespace") }}
    {{- $_ := set $objectValues "kafkaClusterFullName"
          (get $clusterInfo "clusterFullName") }}
  {{- end }}

  {{- /* Change Strimzi label accordingly. */ -}}
  {{- $_ := set $objectValues "labels"
    (merge (default dict $objectValues.labels)
           (dict "strimzi.io/cluster" ($objectValues.kafkaClusterFullName)))
  }}

  {{- $_ := set $objectValues "name"
    (include "base.resources.kafkaUsers.lib.name"
      (dict "applicationNamespace" (default $clusterInfo.namespace $objectValues.applicationNamespace)
            "rootContext"          .rootContext
            "identifier"           (default $identifier $objectValues.nameOverride)
      )
    )
  }}

  {{- /* Check the name is shorter than 64 characters and fail asap if it is not */ -}}
  {{- if (gt (len $objectValues.name) 64) }}
    {{ fail (printf "Error: KafkaUser name exceeds the length limit: '%s' has length %d, but it should be at most 64." $objectValues.name (len $objectValues.name)) }}
  {{- end }}

  {{- /* Concatenate the namespace list where the secret will be replicated */ -}}
  {{- $replicateAnnotation := "" }}
  {{- range
        concat
          (ternary list (list $objectValues.applicationNamespace) (empty $objectValues.applicationNamespace))
          (default (list) $objectValues.replicateToExtraNamespaces)
  }}
  {{- $replicateAnnotation = printf "%s%s%s"
        $replicateAnnotation
        (ternary "" "," (eq $replicateAnnotation ""))
        .
  }}
  {{- end }}
  {{- $_ := set $objectValues "replicateToNamespacesAnnotation" $replicateAnnotation }}

  {{- /* Return the KafkaUser object */ -}}
  {{- $objectValues | toYaml -}}
{{- end -}}
