{{/*
Validate KafkaUser values
*/}}
{{- define "base.resources.kafkaUsers.validate" }}
  {{- $rootContext := .rootContext }}
  {{- $kafkaUserValues := .object }}

  {{- $allowedOperations := list "Alter" "AlterConfigs" "All" "ClusterAction" "Create" "Delete" "Describe" "DescribeConfigs" "IdempotentWrite" "Read" "Write" }}

  {{- if or
        (not (hasKey $kafkaUserValues "authorization"))
        (not (kindIs "map" $kafkaUserValues.authorization))
        (not (hasKey $kafkaUserValues.authorization "acls"))
        (not (kindIs "slice" $kafkaUserValues.authorization.acls))
  }}
    {{- fail (printf "Incorrect or missing ACL list definition in KafkaUser %s. The parameter block .authorization.acls should be defined and be a list. Please refer to the schema documentation." $kafkaUserValues.identifier) }}
  {{- end }}

  {{- range $kafkaUserValues.authorization.acls }}
    {{- if (not (kindIs "map" .)) }}
      {{- fail (printf "Incorrect type for ACL rule in KafkaUser %s: a %s was provided, but a map was expected. Please refer to the schema documentation." $kafkaUserValues.identifier (kindOf .))}}
    {{- end }}
    {{- if or
          (not (hasKey . "operations"))
          (not (kindIs "slice" .operations))
    }}
      {{- fail (printf "Incorrect or missing 'operations' list in ACL rule in KafkaUser %s. The .operations block should be defined in each ACL rule and be a list. Please refer to the schema documentation." $kafkaUserValues.identifier)}}
    {{- end }}

    {{- with .operations }}
      {{- range $op := . }}
        {{- if not (has $op $allowedOperations)}}
          {{- fail (printf "Not a valid operation value for KafkaUser %s: %s." $kafkaUserValues.identifier $op) }}
        {{- end }}
      {{- end }}
    {{- end }}

    {{- if not (has .resource.type (list "cluster" "group" "topic" "transactionalId")) }}
      {{- fail (printf "Resource block for ACL rule in KafkaUser %s might be missing or is referencing an unsupported resource type: %s. The only accepted values are: cluster, group, topic." $kafkaUserValues.identifier .resource.type) }}
    {{- end }}

    {{- if (has .resource.type (list "group" "topic" "transactionalId")) }}
      {{- if not .resource.name }}
        {{- fail (printf "Kafka ACL value inconsistency in KafkaUser %s: when resource.type is \"group\", \"topic\" or \"transactionalId\", the resource name must also be specified." $kafkaUserValues.identifier) }}
      {{- end }}

      {{- if not (regexMatch "^[a-z0-9\\.\\-_]+$" .resource.name) }}
        {{- fail (printf "Wrongly specified Kafka ACL resource name in KafkaUser %s: %s does not match the regex: /^[a-z0-9\\.\\-_]+$/" $kafkaUserValues.identifier .resource.name) }}
      {{- end }}
    {{- end }}

    {{- if and .resource.patternType (not (has .resource.patternType (list "literal" "prefix"))) }}
      {{- fail (printf "Not a valid patternType value for KafkaUser %s: %s. The only accepted values are: prefix, literal." $kafkaUserValues.identifier .resource.patternType) -}}
    {{- end }}
  {{- end }}

  {{- if empty $kafkaUserValues.kafkaCluster }}
    {{- fail (printf "No Kafka cluster specified for KafkaUser %s. Parameter `kafkaCluster` is mandatory." $kafkaUserValues.identifier)}}
  {{- end }}

  {{- $clusterInfo :=
        include "base.resources.kafkaUsers.lib.clusterProperties" $kafkaUserValues.kafkaCluster | fromYaml }}
  {{- if empty $clusterInfo }}
    {{- /* Dynamic error message, always up-to-date with available clusters. */ -}}
    {{- $supportedKafkaClustersDisplayString := "" }}
    {{- range (include "base.resources.kafkaUsers.lib.clusterPropertyMapping" ""
                | fromYaml | keys | sortAlpha) }}
      {{ $supportedKafkaClustersDisplayString = printf "%s%s%s"
            $supportedKafkaClustersDisplayString
            (ternary "" ", " (eq $supportedKafkaClustersDisplayString ""))
            .
      }}
    {{- end }}
    {{- fail (printf "Unsupported Kafka cluster '%s' for KafkaUser %s. Supported values are: %s."
          $kafkaUserValues.kafkaCluster
          $kafkaUserValues.identifier
          $supportedKafkaClustersDisplayString) }}
  {{- end }}


{{- end -}}
