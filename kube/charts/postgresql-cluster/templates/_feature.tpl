{{- /*
Prepare the resources of the CloudNativePG cluster named after the release, using user managed certificates from
cert-manager. These are the objects that were duplicated in every app `postgresql/` folder:
  - certManagerCertificates `ca`: the CA of the cluster, signed by the `issuer` ClusterIssuer
  - certManagerIssuers `main`: the issuer of the leaf certificates, backed by the CA
  - certManagerCertificates `main`, `app` and `replication`: server, app client and streaming_replica client certificates
  - cnpgClusters `main`, using the secrets of these certificates
  - cnpgScheduledBackups `main`, taking volume snapshots

Names come from the base chart: `main` is named after the release, any other id is `<release>-<id>`.

Everything is returned as a default: set `resources.<kind>.<id>...` to override or extend any generated field.

Warning: never delete the `<release>-ca` Secret. The leaf certificates would stay signed by the previous CA and CNPG
deadlocks (https://github.com/cloudnative-pg/cloudnative-pg/issues/10433). Only the 3 leaf secrets are safe to delete.
*/}}
{{- define "postgresql-cluster.feature" }}
{{- $rootContext := .rootContext }}
{{- $values := $rootContext.Values }}
{{- $name := $rootContext.Release.Name }}
{{- $backup := $values.backup | default dict }}

{{- $globalMetadata := tpl (toYaml (($values.defaults | default dict).metadata | default dict)) $rootContext | fromYaml }}
{{- $namespace := $globalMetadata.namespace | default $rootContext.Release.Namespace }}

{{- $dnsNames := list }}
{{- range $service := list "rw" "r" "ro" }}
  {{- $host := printf "%s-%s" $name $service }}
  {{- $dnsNames = concat $dnsNames (list $host (printf "%s.%s" $host $namespace) (printf "%s.%s.svc" $host $namespace) (printf "%s.%s.svc.cluster.local" $host $namespace)) }}
{{- end }}

{{- $reload := dict "labels" (dict "cnpg.io/reload" "") }}
{{- $issuerRef := dict "name" $name "kind" "Issuer" }}

{{- $certificates := dict
      "ca" (dict
        "isCA" true
        "commonName" (printf "%s-ca" $name)
        "secretName" (printf "%s-ca" $name)
        "privateKey" (dict "algorithm" "ECDSA" "size" 256 "rotationPolicy" "Never") 
        "issuerRef" (dict "name" $values.issuer "kind" "ClusterIssuer"))
      "main" (dict
        "secretName" (printf "%s-tls" $name)
        "secretTemplate" $reload
        "dnsNames" $dnsNames
        "issuerRef" $issuerRef)
      "app" (dict
        "secretName" (printf "%s-app-tls" $name)
        "secretTemplate" $reload
        "usages" (list "client auth")
        "commonName" "app"
        "issuerRef" $issuerRef)
      "replication" (dict
        "secretName" (printf "%s-replication-tls" $name)
        "secretTemplate" $reload
        "usages" (list "client auth")
        "commonName" "streaming_replica"
        "issuerRef" $issuerRef) }}

{{- $postgresql := deepCopy ($values.postgresql | default dict) }}
{{- if and $values.clientCertAuth (not (hasKey $postgresql "pg_hba")) }}
  {{- /* https://cloudnative-pg.io/docs/1.28/ssl_connections */}}
  {{- $_ := set $postgresql "pg_hba" (list "hostssl app all all cert") }}
{{- end }}

{{- $cluster := dict
      "instances" $values.instances
      "certificates" (dict
        "clientCASecret" (printf "%s-ca" $name)
        "replicationTLSSecret" (printf "%s-replication-tls" $name)
        "serverTLSSecret" (printf "%s-tls" $name)
        "serverCASecret" (printf "%s-tls" $name))
      "storage" (dict "size" $values.storageSize) }}
{{- if $postgresql }}
  {{- $_ := set $cluster "postgresql" $postgresql }}
{{- end }}

{{- $scheduledBackups := dict }}
{{- if $backup.enabled }}
  {{- /* snapshotOwnerReference: removing the Backup object removes the VolumeSnapshot */}}
  {{- $_ := set $cluster "backup" (dict "volumeSnapshot" (dict
        "className" $backup.snapshotClass
        "snapshotOwnerReference" "backup")) }}

  {{- /* backupOwnerReference: removing the schedule removes the Backup object */}}
  {{- $_ := set $scheduledBackups "main" (dict
        "schedule" $backup.schedule
        "backupOwnerReference" "self"
        "immediate" true
        "method" "volumeSnapshot"
        "cluster" (dict "name" $name)) }}
{{- end }}

{{- /* The instances talk to each other (replication on 5432, status API of the instance manager on 8000) and to the clients.
The operator and the API server are allowed for every cluster by the cluster wide policy of app-cnpg. */}}
{{- $instances := dict "matchLabels" (dict "cnpg.io/cluster" $name) }}
{{- $postgres := dict "ports" (dict "postgres" (dict "port" "5432" "protocol" "TCP")) }}
{{- $peers := dict "ports" (dict "postgres" (dict "port" "5432" "protocol" "TCP") "status" (dict "port" "8000" "protocol" "TCP")) }}
{{- $policy := dict
      "endpointSelector" $instances
      "ingress" (dict
        "instances" (dict "fromEndpoints" (dict "instances" $instances) "toPorts" (dict "postgres" $peers))
        "clients" (dict "fromEndpoints" ($values.clients | default dict) "toPorts" (dict "postgres" $postgres)))
      "egress" (dict
        "instances" (dict "toEndpoints" (dict "instances" $instances) "toPorts" (dict "postgres" $peers))) }}
{{- if not $values.clients }}
  {{- $_ := unset $policy.ingress "clients" }}
{{- end }}

{{- dict "resources" (dict
      "certManagerCertificates" $certificates
      "certManagerIssuers" (dict "main" (dict "ca" (dict "secretName" (printf "%s-ca" $name))))
      "cnpgClusters" (dict "main" $cluster)
      "cnpgScheduledBackups" $scheduledBackups
      "ciliumNetworkPolicies" (dict "main" $policy)) | toYaml }}
{{- end }}
