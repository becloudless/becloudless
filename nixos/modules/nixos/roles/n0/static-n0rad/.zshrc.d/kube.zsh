export PATH="$HOME/.krew/bin:$PATH"
alias klsc="k get pods -o go-template --template='{{range .items}}{{.metadata.name}} ->{{range .spec.containers}}  {{.name}}{{end}}{{\"\n\"}}{{end}}'"
alias klsi="k get pods -o 'jsonpath={range .spec.containers[*]}{.name} -> {.image}{\"\n\"}{end}'"
alias kfail="k get po --all-namespaces -o json | jq '.items[] | {name: .metadata.name, containerStatuses: .status.containerStatuses[]} | select(.containerStatuses.ready == false)  | select(.containerStatuses.lastState.terminated.reason != \"Completed\") |  \"\\(.name).\\(.containerStatuses.name) \\(.containerStatuses.restartCount)\"'"
alias kpdb0="k get pdb -A -o json  | jq -r '.items[] | select(.status.disruptionsAllowed == 0) | .metadata.namespace + \"/\" + .metadata.name'"
# kubectl exec --namespace=manadr-dev -it $(kubectl get pod -l "service=mysql" --namespace=manadr-dev -o jsonpath='{.items[0].metadata.name}') -- bash
