{ config, lib, ... }:

{
  config = lib.mkIf config.bcl.role.enable {
    services.openssh = {
      enable = true;
      hostKeys = [
        {
          path = "/nix/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    programs.ssh.knownHosts = {
      "gitea.bcl.io" = {
        hostNames = [ "gitea.bcl.io" ];
        publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDFxcxYrmKjigJL+D9rcd2hfNwH5d9jje4fD0qQdY7S9EgO4qPQswfD3wQyZ7v1NTibHTLAHwXBxqUpZzb4WxvdhmJxICwnasKTx28ZDgh+R2RmDBPc4Wn9eFGxj7Z2XsT0d4GmDYzt7BCu9FJN526+lCz2wAWfylDoj/frwdT8FM7Sh3wX6zUvXNeF0BayFqgLKQqBefOGsjqyh0mEJdFOYRd/uLBxUpcaiqtZsARKqWPHhn0L1t5c3cX9qddJul+zdFnWRtFV3FxCbST/mQaRka7AhyP95F8W352nNHlhdiBx2DshGL2nZbX3dXUNX7ICVck2pFkJvDowDY+m5o0PI2TJOzp/fRqhYbceXP5FbeD5zws/uQe4fWXlOb6+Ip9EF5rDHktQXZa+PIOnaPltGQA4EakXhr6J2nhzh3sjyMMBvgA7JE9YqXJ1IgB2rVuQp2vau2GNF5jqqsjXOtEkMxIhHU3ECS1aUKc5YwEfm57bFym3Irf+EGJiIkoHTWxgD3wGIur2wBGA2UzZ/nnjaneXE6Yp2ef80+dE/4NKyk7QON20v+vbi4t+rerjWT0wv4f+6r8CXLERbO4gNLIiSPy3MR9UP3a8rLqBf3VmdtY5PsdfwWyS1KnhK23ijqEQPDuQPqqKSPUSgkKI+J2EOhhFAUae/DM89AYDpz0UEw==";
      };
      # "media.bcl.io" = {
      #   hostNames = [ "media.bcl.io" ];
      #   publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKMy79RcoB/CClQTrE8OHtbfTOq9xgCV+gxO3jC2X3Xk n0rad@n0l2";
      # };
      "github.com" = {
        hostNames = [ "github.com" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };
      srv-backup = {
        hostNames = [ "srv-backup" "192.168.40.49" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIqzMzwoNe1lulCw2vkcahrnkJ4uvSDWi0pINdZ7zrcI";
      };
      srv = {
        hostNames = [
          "srv11.h.bcl.io" "192.168.41.11"
          "srv12.h.bcl.io" "192.168.41.12"
          "srv13.h.bcl.io" "192.168.41.13"
          "srv14.h.bcl.io" "192.168.41.14"
          "srv15.h.bcl.io" "192.168.41.15"
          "srv16.h.bcl.io" "192.168.41.16"
          "srv17.h.bcl.io" "192.168.41.17"
          "srv21.h.bcl.io" "192.168.41.21"
          "srv22.h.bcl.io" "192.168.41.22"
          "srv23.h.bcl.io" "192.168.41.23"
          "srv24.h.bcl.io" "192.168.41.24"
          "srv25.h.bcl.io" "192.168.41.25"
          "srv26.h.bcl.io" "192.168.41.26"
          "srv27.h.bcl.io" "192.168.41.27"
        ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzdxzTZmSnjHP85DRhUNTNrJJCpc9WvMk2UbSJ+qnVR";
      };
    };
  };
}
