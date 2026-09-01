{ config, lib, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "serverKube") {
    virtualisation.containerd = {
      enable = true;
      settings = {
        plugins."io.containerd.grpc.v1.cri".containerd = {
          runtimes.runc = {
            runtime_type = "io.containerd.runc.v2";
            options.SystemdCgroup = true; # match kubelet's cgroupDriver: systemd
          };
        };
      };
    };

    environment.persistence."/nix" = {
      hideMounts = true;
      directories = lib.optional (!lib.any (p: p.mountpoint == "/var/lib/containerd") (lib.attrValues config.bcl.diskSystem.extraPartitions))
        { directory = "/var/lib/containerd"; mode = "u=rwx,g=,o="; };
    };
  };

}
