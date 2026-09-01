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

    environment.persistence.${config.bcl.diskSystem.persistRoot} = {
      hideMounts = true;
      directories = lib.optional (!(config.fileSystems ? "/var/lib/containerd")) { directory = "/var/lib/containerd"; mode = "u=rwx,g=,o="; };
    };
  };

}
