{ config, lib, pkgs, ... }: {

  config = lib.mkIf (config.bcl.role.name == "n0") {
    #  TODO: move all that somewher else

    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        ovmf = {
          enable = true;
          packages = [(pkgs.OVMF.override {
            secureBoot = true;
            tpmSupport = true;
          }).fd];
        };
      };
    };

    environment.systemPackages = with pkgs; [
      virtiofsd
      virt-manager
    ];


    users.users.n0rad = {
      extraGroups = [ "libvirtd" ];
    };


    home-manager.users."${config.bcl.wm.user}" = { lib, pkgs, ... }: {
      dconf.settings = with lib.hm.gvariant; {
        "org/virt-manager/virt-manager" = {
          xmleditor-enabled = true;
        };

        "org/virt-manager/virt-manager/confirm" = {
          forcepoweroff = false;
        };
      };

    };

  };
}
