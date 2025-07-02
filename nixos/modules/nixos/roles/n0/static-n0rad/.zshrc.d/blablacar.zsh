alias tshl="tsh --proxy=teleport.corp.blablacar.com login"
alias land="tsh ssh -A root@landing2"

export CONSUL_HTTP_TOKEN_FILE=~/.config/bbc/.onelogin-id-token
# export CONSUL_HTTP_ADDR=https://consul.staging-1.blbl.cr
export CONSUL_HTTP_ADDR=https://consul.tools-1.blbl.cr
# export OP_SESSION_blablacar="XXXXXXXXXXXXXX"

# function sssh() {
  # b="echo $(base64 -w0 ~/.coreos-alias.sh) | base64 --decode > /tmp/remote_ssh_env.sh; exec bash --rcfile /tmp/remote_ssh_env.sh";
  # ssh -A -t $@ "$b";
# };


# source <(bbc completion --zsh)

function chpwd() {
  type __start_kubectl &>/dev/null || source <(kubectl completion zsh)


  eval $(/home/n0rad/Work/Blablacar/repos/ep/kube-manifests/bin/flux-context)
  KUBE_PATH_CLUSTER=$FLUX_CLUSTER
  KUBE_PATH_NAMESPACE=$FLUX_NAMESPACE
  KUBE_PATH_KUBECONFIG=$FLUX_KUBECONFIG

  export KUBECONFIG=$KUBE_PATH_KUBECONFIG

  if [ ! -z $KUBE_PATH_CLUSTER  ]; then
    if [ -z $KUBE_PATH_NAMESPACE ]; then
      alias k="kubectl"
      unalias stern 2>/dev/null
    else
      alias k="kubectl -n $KUBE_PATH_NAMESPACE"
      alias stern="stern -n $KUBE_PATH_NAMESPACE"
      alias kd="kubectl-debug -n $KUBE_PATH_NAMESPACE"
      alias k9s="k9s -n $KUBE_PATH_NAMESPACE"
    fi
  else
    alias k="kubectl"
    unalias stern 2>/dev/null
    unalias kd 2>/dev/null
    unalias k9s 2>/dev/null
  fi
}
