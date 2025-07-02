{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name == "srv") {
    bcl.disk.encrypted = true;
    bcl.role.setN0radPassword = true;
    bcl.boot.ssh = true;

    security.sudo.wheelNeedsPassword = false;
    environment.systemPackages = with pkgs; [
      mergerfs
    ];

    #  sshfs -o sftp_server="/run/wrappers/bin/sudo \$(nix-store -q \$(which ssh))/libexec/sftp-server" srv21:/data_media/ ~/Mount/World

    users.users.root.packages = with pkgs; [
      (writeShellScriptBin "kube-reboot" ''
        kubectl --kubeconfig=/etc/kubernetes/admin.conf drain ${config.networking.hostName} --timeout 200s --ignore-daemonsets --delete-emptydir-data || true
        systemctl reboot
      '')
      (writeShellScriptBin "kube-poweroff" ''
        kubectl --kubeconfig=/etc/kubernetes/admin.conf drain ${config.networking.hostName} --timeout 200s --ignore-daemonsets --delete-emptydir-data || true
        systemctl poweroff
      '')
    ];
  };
}
