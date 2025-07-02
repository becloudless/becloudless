{ config, lib, pkgs, ... }: {

  config = lib.mkIf (config.bcl.role.name == "n0") {

    systemd.tmpfiles.rules = [
      "d /nix/home/n0rad 0700 n0rad users"
      "d /nix/home/n0rad/Syncthing 0700 n0rad users"
    ] ;

    sops.secrets."syncthing.${config.networking.hostName}.cert" = {
      owner = "n0rad";
      sopsFile = ../n0.secrets.yaml;
      path = "/nix/home/n0rad/Syncthing/cert.pem";
    };
    sops.secrets."syncthing.${config.networking.hostName}.key" = {
      owner = "n0rad";
      sopsFile = ../n0.secrets.yaml;
      path = "/nix/home/n0rad/Syncthing/key.pem";
    };

    services.syncthing = {
      enable = true;
      user = "n0rad";
      dataDir = "/nix/home/n0rad";
      configDir = "/nix/home/n0rad/Syncthing";
      settings = {
        options = {
          localAnnounceEnabled = false;
          relaysEnabled = true;
          urAccepted = -1;
          listenAddresses = [
            "relay://syncthing.bcl.io:22067/?id=BWIDMUV-Q7DADJF-W5B7IHY-C5KVAJO-IW2DDRT-D7GLAUC-WUAW42C-VJMIBAL"
          ];
        };
        gui = {
          user = "n0rad";
          password = "dummyPassword"; # TODO
        };
        devices = {
          "n0rad.syncthing.bcl.io" = {
            id = "6O3PPAB-ENQ3AP5-4UE5Y4F-7VYZCPV-LXJB5SB-VD36MHW-LCCBK5D-G6WL4AK";
            autoAcceptFolders = false;
            # addresses = [ "tcp://n0rad.syncthing.bcl.io:22000" ];
          };
          "kwiskas.syncthing.bcl.io" = {
            id = "7DQXWLD-LNZYQA6-INQ72LR-DAXWOUT-XYNDJL3-B7DG3N2-JL4OIOR-WWCVUQ7";
            autoAcceptFolders = false;
            # addresses = [ "tcp://kwiskas.syncthing.bcl.io:22001" ];
          };
        };
        folders = {
         "Home" = {
            id = "rgg5e-vxewr";
            path = "/nix/users/home/n0rad";
            devices = [ "n0rad.syncthing.bcl.io" ];
            fsWatcherEnabled = false;
            rescanIntervalS = 3600; # 1h
          };
         "Documents" = {
            id = "h9jyj-tef5s";
            path = "/nix/home/n0rad/Documents";
            devices = [ "n0rad.syncthing.bcl.io" ];
          };
         "Downloads" = {
            id = "gw3yj-fjhar";
            path = "/nix/home/n0rad/Downloads";
            devices = [ "n0rad.syncthing.bcl.io" ];
          };
         "Pictures" = {
            id = "jkxu9-vi2xh";
            path = "/nix/home/n0rad/Pictures";
            devices = [ "n0rad.syncthing.bcl.io" ];
          };
         "Work" = {
            id = "ehjwd-9dxtm";
            path = "/nix/home/n0rad/Work";
            devices = [ "n0rad.syncthing.bcl.io" ];
          };
         "Archives" = {
            id = "pmwa9-ev5uj";
            path = "/nix/home/n0rad/Archives";
            devices = [ "n0rad.syncthing.bcl.io" ];
          };
         "DCIM" = {
            id = "vwywh-2ubm2";
            path = "/nix/home/n0rad/DCIM";
            devices = [ "n0rad.syncthing.bcl.io" ];
          };
         "Isa-Documents" = {
            id = "w9tqd-uzghb";
            path = "/nix/home/n0rad/Isa/Documents";
            devices = [ "kwiskas.syncthing.bcl.io" ];
          };
         "Isa-Desktop" = {
            id = "p2hfc-nmszo";
            path = "/nix/home/n0rad/Isa/Desktop";
            devices = [ "kwiskas.syncthing.bcl.io" ];
          };
         "Isa-DCIM" = {
            id = "amnaz-xhqix";
            path = "/nix/home/n0rad/Isa/DCIM";
            devices = [ "kwiskas.syncthing.bcl.io" ];
          };
        };
      };
    };


    environment.persistence."/nix" = {
      hideMounts = true;
      users.n0rad = {
        directories = [
          "Archives"
          "Work"
          "Documents"
          "Downloads"
          "Pictures"
          "DCIM"
          "Games"
        ];
      };
    };

    # keep on syncthing
    environment.persistence."/nix/users" = {
      hideMounts = true;
      users.n0rad = {
        directories = [
          ".mozilla" # firefox/ and native-messaging-hosts/ for keepassxc

          # ".viminfo"
          ".tmux"
          # ".lesshst" # less replace the file
          ".docker" # must be the directory so it can mounted by bbc commands
          ".vscode-oss"
          ".config/chromium"
          ".local/bin" # scripts and bbc
          ".local/share/applications" # to keep plex chromium application
          ".local/share/desktop-directories"
          ".local/share/zoxide"
          ".config/menus" # .desktop applications into menu
          ".local/share/icons" # .desktop icons
          ".config/gcloud"
          ".config/sops" # TODO replace by static
          ".config/VSCodium"
          ".wine"

          ".local/share/JetBrains/" # plugins and license
          ".config/JetBrains" # looks required for license
          ".java/.userPrefs/jetbrains"
        ];
        files = [
          ".z"
          ".local/share/gnome-shell/application_state" # trusted .desktop applications
        ];
      };
    };

    system.activationScripts.script.text = ''
      mkdir -p /var/lib/AccountsService/{icons,users}
      cp /nix/home/n0rad/Pictures/face.png /var/lib/AccountsService/icons/n0rad
      echo -e "[User]\nSession=gnome\nIcon=/var/lib/AccountsService/icons/n0rad\n" > /var/lib/AccountsService/users/n0rad
    '';
  };
}
