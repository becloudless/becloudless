{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.serverKube;

  # Set on the node by `kube-drain` when it cordons it, so the node is uncordoned at the next boot (and only then: a node cordoned by hand stays so).
  uncordonAnnotation = "becloudless.net/uncordon-on-boot";

  # Masters have the cluster admin kubeconfig. Workers hold the cluster CA (see serverKubeWorker.nix), so they sign a short-lived admin client
  # certificate: their own node identity is not allowed to evict pods nor to cordon.
  kubeLib = ''
    setup_kubeconfig() {
      ${if cfg.worker then ''
      umask 077
      mkdir -p /run/kube-drain
      kubeadm kubeconfig user --client-name kube-drain --org system:masters --validity-period 1h \
        --config /etc/kubernetes/kubeadm-worker.yaml > /run/kube-drain/kubeconfig.new
      mv /run/kube-drain/kubeconfig.new /run/kube-drain/kubeconfig
      export KUBECONFIG=/run/kube-drain/kubeconfig
      '' else ''
      export KUBECONFIG=/etc/kubernetes/admin.conf
      ''}
    }
  '';

  # Drains the node, respecting the PodDisruptionBudgets: the eviction is retried until the budgets allow it, or the timeout is reached.
  kubeDrain = pkgs.writeShellApplication {
    name = "kube-drain";
    runtimeInputs = [ pkgs.kubernetes pkgs.coreutils ];
    text = ''
      ${kubeLib}
      setup_kubeconfig
      node=${config.networking.hostName}
      if [ "$(kubectl get node "$node" -o jsonpath='{.spec.unschedulable}')" != true ]; then
        kubectl annotate node "$node" ${uncordonAnnotation}=true --overwrite
      fi
      timeout ${toString (cfg.shutdownDrainTimeout + 30)} kubectl drain "$node" --timeout ${toString cfg.shutdownDrainTimeout}s --ignore-daemonsets --delete-emptydir-data
    '';
  };

  # At boot, uncordon the node if it was cordoned by `kube-drain`.
  kubeUncordonOnBoot = pkgs.writeShellApplication {
    name = "kube-uncordon-on-boot";
    runtimeInputs = [ pkgs.kubernetes pkgs.coreutils ];
    text = ''
      ${kubeLib}
      node=${config.networking.hostName}
      for _ in $(seq 120); do
        if setup_kubeconfig && value=$(kubectl get node "$node" -o jsonpath='{.metadata.annotations.becloudless\.net/uncordon-on-boot}' 2>/dev/null); then
          if [ "$value" = true ]; then
            kubectl uncordon "$node" && kubectl annotate node "$node" ${uncordonAnnotation}-
          fi
          break
        fi
        sleep 5
      done
    '';
  };

  # Runs under a logind delay inhibitor lock (see the `kube-drain` service): waits for the system to be asked to shut down, then drains
  # the node. logind only goes on with the shutdown once this exits (or after `InhibitDelayMaxSec`), so everything is still up.
  kubeDrainOnShutdown = pkgs.writeShellApplication {
    name = "kube-drain-on-shutdown";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      until [ "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager PreparingForShutdown)" = "b true" ]; do
        sleep 1
      done
      ${kubeDrain}/bin/kube-drain || echo "kube-drain failed or timed out, shutting down anyway"
    '';
  };

  after = [ "network-online.target" "crio.service" "kubelet.service" ] ++ lib.optional cfg.worker "haproxy-apiserver.service";
in
{
  options.bcl.role.serverKube.shutdownDrainTimeout = lib.mkOption {
    type = lib.types.ints.positive;
    default = 300;
    description = ''
      Maximum time in seconds the node waits, when the system is rebooted or powered off (`systemctl reboot`, power button, ...), for
      its pods to be evicted while respecting the PodDisruptionBudgets. Once over, the shutdown goes on without waiting any longer.
    '';
  };

  config = lib.mkIf (config.bcl.role.name == "serverKube") {
    users.users.root.packages = [ kubeDrain ];

    # Drain the node, respecting the PodDisruptionBudgets, whatever triggers the reboot/poweroff through logind (`systemctl reboot`, power
    # button, ...). It cannot be done in the ExecStop of a service: the containers run in systemd scopes that are stopped as soon as the
    # shutdown starts, so the apiserver proxy is already gone by then. Instead the service holds a logind delay inhibitor lock: logind only
    # starts the shutdown once the drain is over, with the whole system still running.
    # Do not use the kubelet graceful node shutdown (`shutdownGracePeriod`) next to it: the kubelet would kill the pods as soon as logind
    # announces the shutdown, before the drain.
    services.logind.settings.Login.InhibitDelayMaxSec = cfg.shutdownDrainTimeout + 60;

    systemd.services."kube-drain" = {
      description = "Drain the kubernetes node before a shutdown";
      inherit after;
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = false; # a deployment must not drain the node
      stopIfChanged = false;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=shutdown --mode=delay --who=kube-drain --why=\"Draining the kubernetes node\" ${kubeDrainOnShutdown}/bin/kube-drain-on-shutdown";
      };
    };

    systemd.services."kube-uncordon-on-boot" = {
      description = "Uncordon the kubernetes node if it was cordoned by kube-drain";
      inherit after;
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${kubeUncordonOnBoot}/bin/kube-uncordon-on-boot";
      };
    };
  };
}
