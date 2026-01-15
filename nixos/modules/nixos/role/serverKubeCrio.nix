{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "serverKube") {
    environment.systemPackages = with pkgs; [
      cri-o
    ];

    systemd.services."crio" = {
      path = [ pkgs.cri-o ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.cri-o}/bin/crio";
        ExecReload="${pkgs.coreutils}/bin/kill -s HUP $MAINPID";
        TasksMax = "infinity";
        LimitNOFILE = 1048576;
        LimitNPROC = 1048576;
        LimitCORE = "infinity";
        OOMScoreAdjust = -999;
        TimeoutStartSec = 0;
        Restart = "on-failure";
        RestartSec = 10;
      };
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      before = [ "kubelet.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    environment.etc = let
      mkRegistry = name: {
        name = "containers/registries.conf.d/${name}.conf";
        value = {
          text = ''
            [[registry]]
            prefix = "${name}"
            location = "${name}"           # if mirror fail, fetching upstream
            # location = "docker.${config.bcl.global.domain}"    # replace location with mirror. mirror is mandatory

            [[registry.mirror]]
            location = "docker.${config.bcl.global.domain}"
          '';
        };
      };
    in builtins.listToAttrs [
      (mkRegistry "registry.k8s.io")
      (mkRegistry "docker.io")
      (mkRegistry "registry-1.docker.io")
      (mkRegistry "docker.${config.bcl.global.domain}")
      (mkRegistry "registry.${config.bcl.global.domain}")
      (mkRegistry "quay.io")
      (mkRegistry "ghcr.io")
      (mkRegistry "tccr.io") # truecharts
      (mkRegistry "nvcr.io") # nvidia
      {
        name = "crio/crio.conf.d/${config.bcl.global.domain}.crio.conf";
        value = {
          text = ''
             [crio.network]
             plugin_dirs = ["/opt/cni/bin/", "/usr/libexec/cni"]

             [crio.runtime]
             #conmon_cgroup = "pod"
             cgroup_manager = "systemd"

             hooks_dir = ["/usr/share/containers/oci/hooks.d"]
             pids_limit = 2048
             default_capabilities = [
             "CHOWN",
             "DAC_OVERRIDE",
             "FSETID",
             "FOWNER",
             "SETGID",
             "SETUID",
             "SETPCAP",
             "NET_BIND_SERVICE",
             "KILL",
             "SYS_CHROOT",
             ]
             #default_sysctls = [
             #      "net.ipv4.ping_group_range = 0   2147483647",
             #]

             [crio.metrics]
             enable_metrics = true
             metrics_port = 9092
           '';
        };
      }
      {
        name = "containers/registries.conf.d/unqualified.conf";
        value = {
          text = ''
          unqualified-search-registries = ['docker.io']
        '';
        };
      }
      {
        name = "containers/policy.json";
        value = {
         text = ''
            {
                "default": [
                    {
                        "type": "insecureAcceptAnything"
                    }
                ],
                "transports":
                    {
                        "docker-daemon":
                            {
                                "": [{"type":"insecureAcceptAnything"}]
                            }
                    }
            }
          '';
        };
      }
    ];

    environment.persistence."/nix" = {
      hideMounts = true;
      directories = [
        { directory = "/var/lib/containers"; mode = "u=rwx,g=,o="; }
      ];
    };
  };

}