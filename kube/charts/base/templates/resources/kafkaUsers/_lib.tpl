{{- define "base.resources.kafkaUsers.lib.clusterPropertyMapping" }}
  {{- $clusterInfoMapping := dict
        "gillbus"   (dict "namespace"        "dbre"
                          "clusterFullName"  "gillbus-kafka")
        "platform"  (dict "namespace"        "platform"
                          "clusterFullName"  "platform-kafka")
        "analytics" (dict "namespace"        "analytics"
                          "clusterFullName"  "analytics-kafka")
        "test"      (dict "namespace"        "dbre"
                          "clusterFullName"  "test-kafka")
  }}

  {{- $clusterInfoMapping | toYaml -}}
{{- end }}

{{- define "base.resources.kafkaUsers.lib.clusterProperties" }}
  {{- $clusterInfoMapping :=
        include "base.resources.kafkaUsers.lib.clusterPropertyMapping" "" | fromYaml -}}
  {{ $kafkaCluster := default "" . }}
  {{- if (hasKey $clusterInfoMapping $kafkaCluster) -}}
    {{- $res := get $clusterInfoMapping $kafkaCluster | toYaml }}
    {{- $res -}}
  {{- else }}
    {{- /* Fail silently, let validation templates do their job. */ -}}
    {{- dict | toYaml -}}
  {{- end -}}
{{- end -}}

{{- define "base.resources.kafkaUsers.lib.name" }}
  {{- /*
      How to call this template function: as function argument, pass
      a dict with those keys:
          1. `applicationNamespace`: the namespace of the app owning this KafkaUser
          2. `rootContext`: the root Helm context
          3. `identifier`: the base-template identifier of the KafkaUser resource,
             e.g. the Kafka cluster short name followed by the
             workload name ("platform-main").

  */ -}}

  {{- if not (and
        (hasKey . "applicationNamespace")
        (hasKey . "rootContext")
        (hasKey . "identifier")
  ) }}
    {{- fail "Missing one or several parameters in the context passed to \"base.resources.kafkaUsers.lib.name\"." }}
  {{- end }}

  {{- printf "%s-%s-%s"
        (.applicationNamespace | lower)
        (include "base.lib.chart.names.fullname" .rootContext | lower)
        (.identifier | lower)
  }}
{{- end }}
