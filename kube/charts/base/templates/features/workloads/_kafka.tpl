{{- define "base.workloads.kafka" -}}
  {{- $rootContext := .rootContext -}}
  {{- $workloadId := .workloadId -}}
  {{- $workload := .workload -}}
  {{- if include "base.lib.utils.isEnabled" (dig "kafka" "clusters" dict $workload) -}}
resources:
  kafkaUsers:
    {{- range $kafkaCluster, $kafkaConfig := $workload.kafka.clusters }}
    {{- /* Condition: create KafkaUser only if some ACLs are listed */ -}}
    {{- if or $kafkaConfig.readWriteTopics
              $kafkaConfig.writeTopics
              $kafkaConfig.readTopics
              $kafkaConfig.transactionalIds
    -}}
      {{- $kafkaClusterFullName :=
        get
          (include "base.resources.kafkaUsers.lib.clusterProperties" $kafkaCluster | fromYaml)
          "clusterFullName"
      }}
    {{ $identifier := printf "%s-%s" $kafkaCluster $workloadId }}
    {{ $identifier }}:
      kafkaCluster: {{ $kafkaCluster }}
      applicationNamespace: {{ $rootContext.Release.Namespace }}
      authorization:
        acls:
          {{- /* Read topics */ -}}

          {{- range $topicName, $topicConfig := default dict $kafkaConfig.readTopics }}
          - operations:
              - "Read"
              - "Describe"
              - "DescribeConfigs"
            resource:
              type: "topic"
              name: {{ $topicName }}
              patternType: {{ default "literal" $topicConfig.patternType }}
          {{- end }}

          {{- /* Read-write topics */ -}}

          {{- range $topicName, $topicConfig := default dict $kafkaConfig.readWriteTopics }}
          - operations:
              - "Read"
              - "Write"
              - "Describe"
              - "DescribeConfigs"
            resource:
              type: "topic"
              name: {{ $topicName }}
              patternType: {{ default "literal" $topicConfig.patternType }}
          {{- end }}

          {{- /* Write topics */ -}}

          {{- range $topicName, $topicConfig := default dict $kafkaConfig.writeTopics }}
          - operations:
              - "Write"
              - "Describe"
              - "DescribeConfigs"
            resource:
              type: "topic"
              name: {{ $topicName }}
              patternType: {{ default "literal" $topicConfig.patternType }}
          {{- end }}

          {{- /* Transactional ID */ -}}

          {{- if not $kafkaConfig.transactionalId }}
            {{- /* By default, to ease migration, we try to guess the
                   transactional ID from other locations. */ -}}
            {{- with (dig "spring" "config" "bbc" "clients" "kafka" "producer" "transactionalId" nil $workload) }}
              {{- $_ := set $kafkaConfig "transactionalId" . }}
            {{- end }}
          {{- end }}

          {{- with $kafkaConfig.transactionalId }}
          - operations:
              - "Write"
              - "Describe"
            resource:
              type: "transactionalId"
              name: {{ . }}
              patternType: "literal"
          {{- end }}

          {{- /* Consumer group permissions, if needed */ -}}

          {{- if (or $kafkaConfig.readTopics $kafkaConfig.readWriteTopics) }}
          {{- if not $kafkaConfig.consumerGroup }}
          {{ fail (printf "You must specify a kafka.clusters.%s.consumerGroup value. Indeed, we need to allow your app to consume your Kafka topics using this consumerGroup. If you need help, please ask DBRE." $kafkaCluster) }}
          {{- end }}
          - operations:
              - "Read"
              - "Describe"
            resource:
              type: "group"
              name: {{ $kafkaConfig.consumerGroup }}
          {{- end }}
    {{- end }}
    {{- end }}
  {{- end -}}
{{- end }}
