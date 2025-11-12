{ inputs, config, lib, pkgs, ... }: {

  bcl = {
    global = {
      enable = true;
    };
  };

  users.users.nixos.openssh.authorizedKeys.keys = lib.mkIf (config.bcl.global.admin != null) (
    lib.mapAttrsToList (_: u: u.sshPublicKey)
      (lib.filterAttrs (_: u: u.sshPublicKey != null) config.bcl.global.admin.users)
  );

  environment.systemPackages = with pkgs; [ nixos-facter ];

  services.getty.helpLine = lib.mkForce "";
  programs.bash.interactiveShellInit = ''
    echo ">> Waiting for network to be ready..."
    count=0
    while true; do
        if [ $(systemctl is-active network-online.target) == "active" ]; then
            break
        fi
        if [ "$count" == "15" ]; then
          echo "Network not available"
          exit 1
        fi
        sleep 1
        var=$((var + 1))
    done

    echo ">>"
    echo ">> Run  'bcl nixos install $(ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)'  on another device where bcl is available, to install this device"
    echo ">>"
  '';

  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  isoImage.volumeID = lib.mkForce "bcl-iso";
  isoImage.isoName = lib.mkForce "bcl.iso";
}
