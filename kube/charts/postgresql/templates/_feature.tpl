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
{{- define "postgresql.feature" }}
{{- $rootContext := .rootContext }}
{{- $values := $rootContext.Values }}
{{- $name := $rootContext.Release.Name }}
{{- $backup := $values.backup | default dict }}

{{- $globalMetadata := tpl (toYaml (($values.defaults | default dict).metadata | default dict)) $rootContext | fromYaml }}
{{- $namespace := $globalMetadata.namespace | default $rootContext.Release.Namespace }}

{{- $postgresql := deepCopy ($values.postgresql | default dict) }}
{{- if and $values.clientCertAuth (not (hasKey $postgresql "pg_hba")) }}
  {{- /* https://cloudnative-pg.io/docs/1.28/ssl_connections */}}
  {{- $_ := set $postgresql "pg_hba" (list "hostssl app all all cert") }}
{{- end }}

{{- /* The WAL has to fit in the volume next to the data, on every instance: the defaults of CloudNativePG
(max_wal_size 1GB, wal_keep_size 512MB) fill a small one, and the instance refuses to start with
`Not enough WAL disk space`. They are a fraction of the size of the volume, the defaults are the upper bound.
Parameters set by the user take precedence. */}}
{{- $sizeMi := include "postgresql.sizeMi" $values.storageSize | int64 }}
{{- $parameters := $postgresql.parameters | default dict }}
{{- $walParameters := dict
  "max_wal_size" (printf "%dMB" (min (div $sizeMi 4) 1024))
  "min_wal_size" (printf "%dMB" (min (div $sizeMi 32) 80))
  "wal_keep_size" (printf "%dMB" (min (div $sizeMi 8) 512))
  "max_slot_wal_keep_size" (printf "%dMB" (min (div $sizeMi 4) 4096))
}}
{{- range $key, $value := $walParameters }}
  {{- if not (hasKey $parameters $key) }}
    {{- $_ := set $parameters $key $value }}
  {{- end }}
{{- end }}
{{- $_ := set $postgresql "parameters" $parameters }}

resources:
  certManagerCertificates:
    ca:
      isCA: true
      commonName: {{ $name }}-ca
      secretName: {{ $name }}-ca
      privateKey:
        algorithm: ECDSA
        size: 256
        rotationPolicy: Never
      issuerRef:
        name: {{ $values.issuer }}
        kind: ClusterIssuer
    main:
      secretName: {{ $name }}-tls
      secretTemplate:
        labels:
          cnpg.io/reload: ""
      dnsNames:
        {{- range $service := list "rw" "r" "ro" }}
        {{- $host := printf "%s-%s" $name $service }}
        - {{ $host }}
        - {{ $host }}.{{ $namespace }}
        - {{ $host }}.{{ $namespace }}.svc
        - {{ $host }}.{{ $namespace }}.svc.cluster.local
        {{- end }}
      issuerRef:
        name: {{ $name }}
    app:
      secretName: {{ $name }}-app-tls
      secretTemplate:
        labels:
          cnpg.io/reload: ""
      usages:
        - client auth
      commonName: app
      issuerRef:
        name: {{ $name }}
    replication:
      secretName: {{ $name }}-replication-tls
      secretTemplate:
        labels:
          cnpg.io/reload: ""
      usages:
        - client auth
      commonName: streaming_replica
      issuerRef:
        name: {{ $name }}

  certManagerIssuers:
    main:
      ca:
        secretName: {{ $name }}-ca

  cnpgClusters:
    main:
      instances: {{ $values.instances }}
      {{- /* No PodDisruptionBudget: they block the drain of the nodes (kured, upgrades) when the primary is on it */}}
      enablePDB: false
      certificates:
        clientCASecret: {{ $name }}-ca
        replicationTLSSecret: {{ $name }}-replication-tls
        serverTLSSecret: {{ $name }}-tls
        serverCASecret: {{ $name }}-tls
      storage:
        size: {{ $values.storageSize }}
        storageClass: {{ $values.storageClass }}
      {{- if $postgresql }}
      postgresql: {{- $postgresql | toYaml | nindent 8 }}
      {{- end }}
      {{- if $backup.enabled }}
      backup:
        volumeSnapshot:
          className: {{ $backup.snapshotClass }}
          {{- /* snapshotOwnerReference: removing the Backup object removes the VolumeSnapshot */}}
          snapshotOwnerReference: backup
      {{- end }}

  {{- if $backup.enabled }}
  cnpgScheduledBackups:
    main:
      schedule: {{ $backup.schedule | quote }}
      {{- /* backupOwnerReference: removing the schedule removes the Backup object */}}
      backupOwnerReference: self
      immediate: true
      method: volumeSnapshot
      cluster:
        name: {{ $name }}
  {{- end }}

  {{- /* The instances talk to each other (replication on 5432, status API of the instance manager on 8000) and to the clients.
  The operator and the API server are allowed for every cluster by the cluster wide policy of app-cnpg. */}}
  ciliumNetworkPolicies:
    main:
      endpointSelector:
        matchLabels:
          cnpg.io/cluster: {{ $name }}
      ingress:
        instances:
          fromEndpoints:
            instances:
              matchLabels:
                cnpg.io/cluster: {{ $name }}
          toPorts: [5432, 8000]
        {{- if $values.clients }}
        clients:
          fromEndpoints: {{- $values.clients | toYaml | nindent 12 }}
          toPorts: [5432]
        {{- end }}
      egress:
        instances:
          toEndpoints:
            instances:
              matchLabels:
                cnpg.io/cluster: {{ $name }}
          toPorts: [5432, 8000]
{{- end }}

{{- /* A size such as `1Gi`, `512Mi` or `2Ti` in MiB (`M`, `G` and `T` are taken as binary ones too). */}}
{{- define "postgresql.sizeMi" }}
  {{- $size := toString . }}
  {{- $units := dict "Mi" 1 "M" 1 "Gi" 1024 "G" 1024 "Ti" 1048576 "T" 1048576 }}
  {{- if not (regexMatch "^[0-9]+(Mi|M|Gi|G|Ti|T)$" $size) }}
    {{- fail (printf "storageSize `%s` is not supported, use a whole number of Mi, Gi or Ti (ex: 1Gi)" $size) }}
  {{- end }}
  {{- mul (atoi (regexFind "^[0-9]+" $size)) (get $units (regexFind "[A-Za-z]+$" $size)) }}
{{- end }}
