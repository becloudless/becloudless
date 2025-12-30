{ inputs, config, lib, pkgs, ... }: {

  bcl = {
    global = {
      enable = true;
    };
  };

  users.users.nixos.openssh.authorizedKeys.keys = [
    config.bcl.global.admin.users.toto.sshPublicKey
  ];


  environment.systemPackages = with pkgs; [
    nixos-facter
  ];

#  environment.etc."ssh/ssh_host_ed25519_key" = {
#    mode = "0600";
#    source = "${/tmp/install-ssh_host_ed25519_key}";
#  };

  services.getty.helpLine = lib.mkForce "";
#  programs.bash.interactiveShellInit = ''
#    echo ">> Waiting for network to be ready..."
#    count=0
#    while true; do
#        if [ $(systemctl is-active network-online.target) == "active" ]; then
#            break
#        fi
#        if [ "$count" == "15" ]; then
#          echo "Network not available"
#          exit 1
#        fi
#        sleep 1
#        var=$((var + 1))
#    done
#
#
#    echo ">>"
#    echo ">> Run  'bcl nixos install $(ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)'  on another device where bcl is available, to install this device"
#    echo ">>"
#  '';

  # faster compression
  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  isoImage.volumeID = lib.mkForce "bcl-iso";
  isoImage.isoBaseName = lib.mkForce "bcl";
}
