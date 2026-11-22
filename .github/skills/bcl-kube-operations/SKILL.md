---
name: bcl-kube-operations
description: "Use when: diagnosing or repairing a live bcl Kubernetes cluster (Flux HelmRelease/Kustomization failing or stuck, cert-manager certificate pending, CloudNativePG replica or certificate problems, Longhorn volume attach/replica problems, etcd timeouts, Cilium drops, default-deny regressions) and when planning a cutover/migration of apps between Flux Kustomizations and Helm releases without losing data. Read-only diagnosis first, mutation only with approval."
---

# Kubernetes operations in bcl

Read [bcl-agent-workflow](../bcl-agent-workflow/SKILL.md) first: diagnosis is read-only; every patch, delete or apply on a live cluster needs the maintainer's approval, and the fix must also land in the repo (chart or cluster values).
Chart authoring: [bcl-kube-charts](../bcl-kube-charts/SKILL.md).

## Access

- A new terminal has an empty `KUBECONFIG`: export the cluster's kubeconfig first (cluster repos keep them in a git-ignored `.kube/`).
- A control-plane node also works over ssh: `ssh <node> sudo kubectl --kubeconfig /etc/kubernetes/admin.conf <args>`. Quote remote arguments with `printf '%q '` when wrapping kubectl.
- Cilium: `kubectl -n <cilium-ns> exec ds/cilium -- cilium-dbg endpoint list`, `hubble observe --verdict DROPPED` per agent. etcd images have no shell: call `etcdctl` directly with explicit `https://<ip>:2379` endpoints and the certs under `/etc/kubernetes/pki/etcd`.

## Diagnosis flow (read-only)

1. `kubectl get hr,ks -A | grep -v True`, then `kubectl describe hr <name>`: look at `dependsOn` (a failing `-pre` blocks the app), the last error, and whether the HelmRelease is suspended.
2. Pods: `kubectl get pods -A | grep -v Running`, `describe pod` events, `logs --previous`. A pod stuck in `Init` often waits for a Secret/ConfigMap/PVC; `ContainerCreating` for hours often is a volume attach problem.
3. Networking symptoms after a policy rollout: default deny breaks DNS first (allow-dns), then startup checks to external hosts, then webhooks. Use hubble drops per node.
4. Compare live objects with the chart golden (`ci/ci-result.yaml`): leftover fields from older owners survive Helm adoption.
5. Report root cause, evidence, and which part needs the maintainer (commit/push, apply, DNS, port forward).

## Known failure signatures

| Symptom | Cause | Fix |
|---|---|---|
| Certificate pending, challenge self-check `no such host` | public DNS name missing, port 80 not forwarded, or the Gateway has no external address (no LB IP/BGP/pool) so HTTP-01 cannot be served | fix DNS/forwarding/LB pool in the infra code, not by editing the Certificate |
| CNPG replica `Running 0/1`, log `requested WAL segment ... has already been removed` | replica lost WAL and there is no archive | delete the instance PVCs (`-l cnpg.io/cluster=<c>,cnpg.io/instanceName=<pod>`) and pod, the operator re-clones. The `replica-repair` CronJob of `app-cnpg` automates it (also corrupt slot / corrupt WAL cases; DRY_RUN env to test; opt out with annotation) |
| CNPG Cluster stuck `x509: certificate signed by unknown authority` while generating the replication client cert | CA Secret was deleted and recreated, leaf certs are signed by the old CA (upstream CNPG issue 10433) | delete only the 3 leaf secrets (`<app>-postgresql-tls`, `-app-tls`, `-replication-tls`), never the `*-ca` secret; delete a stale `-join` Job and pod; verify with `openssl verify -CAfile ca.crt leaf.crt` |
| RWO pod `ContainerCreating`, `FailedAttachVolume ... attachmentID csi-...` | leaked `csi-attacher` ticket in Longhorn `volumeattachments.longhorn.io` for the old node | remove that ticket with a JSON patch guarded by a `test` op on `/spec/attachmentTickets` node; the `attachment-repair` CronJob of `app-longhorn` automates it |
| Longhorn volume stuck `attaching`, `cannot find disk name for replica` | a disk was re-initialised (new UUID), replica points to the old disk | delete the stale replica only if another healthy replica exists (automated in `attachment-repair`) |
| HelmRelease upgrade stuck, pod `Init` on a missing secret | leftover legacy values on the adopted HelmRelease | JSON-patch the leftover key |
| App fails at start with `i/o timeout` to an external host | missing egress rule under default deny | add `toFQDNs` egress in the app chart |
| Authenticated SMTP times out inside the mail stack | policies only allowed port 25 between components | allow the submission proxy port too |
| `flux reconcile` ok then "server was unable to return a response in the time allotted", controllers restarting | not Flux: a hung etcd member (ping and TCP answer, ssh/logs time out) | `etcdctl endpoint status -w table`; quorum ok means do not restart/remove/defrag anything without approval; defrag is a candidate when most of the DB is free |
| Namespace or PVC stuck Terminating | VolumeSnapshots pin the PVC (pvc-as-source-protection) | delete the snapshots in that namespace first |
| Every Prometheus query returns empty, dashboards blank | the data PVC is full (`no space left on device` in the Prometheus log) because `retentionSize` is larger than the PVC | set `retentionSize` below the PVC size or grow the PVC |

## Changing a cluster safely (cutover between owners)

When moving apps from old Flux Kustomizations to Helm releases (adoption), most data losses came from the old owner coming back:

- Suspending a Kustomization and setting `prune: false` is not durable: the parent Kustomization re-applies the old manifest (resets suspend/prune, re-adds the finalizer) and a deleted Kustomization with prune on garbage collects its whole inventory (namespace, PVCs, PVs with reclaim `Delete`, Longhorn volumes).
- Before the push, for anything stateful: annotate every inventory object `kustomize.toolkit.fluxcd.io/prune=disabled`, set PV reclaim policy to `Retain`, take a Longhorn snapshot/backup, and verify `kubectl get ks <x> -o jsonpath='{.spec.prune}'`. Delete Deployments whose selector changes before the push (a failed first install rolls the release back).
- Right after the push, delete the old Kustomization (patch suspend+prune false+finalizers null first), then force the new release (`reconcile.fluxcd.io/requestedAt` + `forceAt`), delete stale HelmCharts, and delete legacy routes/listeners before the new ones (hostname conflict).
- When the old HelmRelease has the same name as a new inner HelmRelease, delete the old Kustomization (not just suspend) and the old HR before the new one is created: helm-controller sees a changed chart name and uninstalls the release (PVCs and PVs included).
- Old Ingress objects can keep certificates of legacy gateway listeners renewed: do not delete them before the host is exposed by a chart.
- Check for stale Kustomizations of every migrated app afterwards (`kubectl get ks -A`).
- Helm adoption needs labels `app.kubernetes.io/managed-by=Helm` and `meta.helm.sh/release-name|namespace` annotations on adopted objects; mittwald StringSecret skips an unowned pre-existing Secret.
- Kyverno webhook calls can flake on pod create: retry. Policy reports list old pods until they are recreated.
- A Longhorn volume shared by two PVs (static PV + restored PV) must never be deleted when only one PV object is retired.

Write helper scripts to `/tmp`, keep them idempotent, and delete temp files, tokens and port-forwards at the end.
