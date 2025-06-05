```bash

sudo nix-collect-garbage --delete-older-than 14d


nix build .#nixosConfigurations.hideki2.config.system.build.toplevel

nix develop .#kernel


# add package
nix-env -iA nixos.git
nix-env -iA nixos.sops

nixos-rebuild dry-build --flake path:/etc/nixos


nix flake check
# sudo --preserve-env=SSH_AUTH_SOCK
sudo nix --extra-experimental-features 'nix-command flakes' run 'github:nix-community/disko#disko-install' -- --flake .#n0l1 --dry-run


nix --experimental-features "nix-command flakes" repl 
> :lf .
> outputs.nixosConfigurations.n0l1.config.fileSystems

```
# install

```bash
sudo -i
ssh-keygen




nix --extra-experimental-features 'nix-command flakes' --refresh run 'github:nix-community/disko#disko-install' -- --flake git+ssh://git@gitea.bcl.io/bcl/nixos#n0l1 --write-efi-boot-entries --disk main /dev/disk/by-id/ata-APPLE_SSD_SM0512G_S29ANYAG578580
nix --extra-experimental-features 'nix-command flakes' --refresh run 'github:nix-community/disko' -- --flake git+ssh://git@gitea.bcl.io/bcl/nixos#n0l1 --mode mount


```

- install nix
- add ssh key to fetch git repo to ssh-agent
- ask password for filesystem?
- run nix disk-install
- reboot


# user Setup
https://github.com/sebastiant/dotfiles/blob/master/flake.nix
https://gitea.com/hezaki/touka
whole infra deployed with nix: https://gitea.c3d2.de/C3D2/nix-config
whole infra deployed with nix including kube: https://git.mcth.fr/uNixVerse/nix
https://github.com/mic92/dotfiles
hyprland with wayland and full setup: https://github.com/ryan4yin/nix-config
https://github.com/lilyinstarlight/foosteros/blob/9dc10cbc68b56c02cd10642061a14b7fddf8adb5/hosts/bina/disks.nix#L117-L118
https://github.com/LGUG2Z/nixos-hetzner-cloud-starter/blob/master/flake.nix
https://github.com/nix-community/infra/tree/master
https://github.com/reckenrode/nixos-configs
https://github.com/canadaduane/my-nixos-conf/tree/main/system/keyd
https://github.com/canadaduane/my-nixos-conf/tree/main/system
https://github.com/bendlas/nixos-config/blob/net.bendlas/nixos-config/master/power-savings.nix
https://github.com/ElvishJerricco/stage1-tpm-tailscale
https://github.com/srghma/dotfiles/tree/main/nixos
https://gitlab.com/rprospero/dotfiles/-/blob/master/nix/system/ssh.nix
https://github.com/Nafanya/nixos-config/blob/040bcc4e7b5c21508f3720ee385533fb8f584e68/flake.nix#L56
https://git.2li.ch/Nebucatnetzer/nixos
https://github.com/jordanisaacs/dotfiles/blob/master/lib/app.nix
https://github.com/sebastiant/dotfiles/tree/master/hosts/t14-nixos
https://git.sr.ht/~bwolf/dotfiles
https://github.com/nix-community/infra
https://github.com/Quoteme/nixos/blob/master/apps/linux-wifi-hotspot/default.nix
https://github.com/juipeltje/configs/tree/main/
https://github.com/ironman820/flake/tree/main
https://github.com/ironman820/flake
https://github.com/khuedoan/nixos-setup/blob/master/configuration.nix
https://git.sr.ht/~mchrist/dotfiles/tree/master/item/nixos/modules/secureboot.nix
https://nixos.wiki/wiki/Configuration_Collection
https://github.com/PaulGrandperrin/nix-systems/blob/main/nixosModules/shared/wireguard.nix
https://gitea.c3d2.de/c3d2/nix-config


# templates
https://github.com/aldoborrero/templates/tree/main/templates/blog/nix/setting-up-machines-nix-style





# utils
multi channel so have dirrent version per device: https://discourse.nixos.org/t/hostname-based-flake-lock/10578/5
create systemd unit: https://www.reddit.com/r/NixOS/comments/17gtpee/help_making_script_run_at_startup/
getting started with nix env and nur: https://gricad-doc.univ-grenoble-alpes.fr/hpc/softenv/nix/
getting started modules: https://nixos.wiki/wiki/NixOS_modules
build package from master: https://www.reddit.com/r/NixOS/comments/18kf0xe/how_can_i_install_a_specific_version_of_a_package/
nox automatic store handle: https://github.com/nix-community/infra/blob/d1c77d2b2ed49d39838ee08f3529d05cb281d94b/modules/shared/nix-daemon.nix
disko with encryption: https://github.com/nix-community/disko/issues/289
https://mynixos.com/
create usb key: https://aldoborrero.com/posts/2023/01/15/setting-up-my-machines-nix-style/
sops secrets not in store: https://github.com/NixOS/nix/issues/6536
auto upgrade ssh key file: https://www.reddit.com/r/NixOS/comments/126pj64/force_systemautoupgrade_to_use_private_ssh_key/
flake getting started: https://nix-tutorial.gitlabpages.inria.fr/nix-tutorial/flakes.html
install specific version of package: https://nixos-and-flakes.thiscute.world/nixos-with-flakes/downgrade-or-upgrade-packages



#TODO
# https://discourse.nixos.org/t/ssh-agent-not-starting/16858
# https://ferrario.me/using-keepassxc-to-manage-ssh-keys/
# https://www.google.com/search?client=firefox-b-d&q=nixos+systemd+ssh-agent

# https://www.google.com/search?q=nixos+keepassxc+Could+not+open+a+connection+to+your+authentication+agent.&client=firefox-b-d&sca_esv=7f161f12ff9fd306&ei=8i1RZvTVLumrkdUPgJaywAk&ved=0ahUKEwj0lvaaw6eGAxXpVaQEHQCLDJgQ4dUDCBA&uact=5&oq=nixos+keepassxc+Could+not+open+a+connection+to+your+authentication+agent.&gs_lp=Egxnd3Mtd2l6LXNlcnAiSW5peG9zIGtlZXBhc3N4YyBDb3VsZCBub3Qgb3BlbiBhIGNvbm5lY3Rpb24gdG8geW91ciBhdXRoZW50aWNhdGlvbiBhZ2VudC5IAFAAWABwAHgBkAEAmAEAoAEAqgEAuAEDyAEA-AEBmAIAoAIAmAMAkgcAoAcA&sclient=gws-wiz-serp
# https://c3pb.de/blog/keepassxc-secrets-service.html


https://gitlab.com/usmcamp0811/dotfiles
# https://github.com/Misterio77/nix-starter-configs
# https://github.com/Misterio77/nix-config/blob/main/home/misterio/features/desktop/common/firefox.nix
https://discourse.nixos.org/t/combining-best-of-system-firefox-and-home-manager-firefox-settings/37721


https://coder.social/nix-community/impermanence


# Explain nix
https://nixos.org/manual/nix/stable/package-management/profiles.html
ls ~/.nix-profile/etc/
symlink zsh highlights https://discourse.nixos.org/t/how-do-i-create-a-symlink-for-a-file-from-a-package/23006

# monitors

https://discourse.nixos.org/t/proper-way-to-configure-monitors/12341/10

to study: https://github.com/gvolpe/nix-config
to study: https://github.com/bonsairobo/MyNixOs/blob/f3fff2969131350966c8c2def7283829c98ddbdd/configuration.nix#L234-L243
create a kernel derivation : https://gist.github.com/gtgteq/30cb73c344477d26f8c69768e010331a
terraform running a nixos instance on ec2: https://github.com/nix-community/terraform-nixos/blob/master/examples/hermetic_config/configuration.nix


setup: https://gricad-doc.univ-grenoble-alpes.fr/hpc/softenv/nix/
nix syntax in terranix: https://terranix.org/documentation/terranix-vs-hcl.html




mine configuation: https://github.com/ryan4yin/nix-config/blob/main/home/linux/gui/base/xdg.nix
sops with downstream secret nodes: https://github.com/lilyinstarlight/foosteros/blob/9dc10cbc68b56c02cd10642061a14b7fddf8adb5/hosts/bina/configuration.nix
send mails from errors: https://github.com/lilyinstarlight/foosteros/blob/9dc10cbc68b56c02cd10642061a14b7fddf8adb5/hosts/bina/configuration.nix
    https://github.com/lilyinstarlight/foosteros/blob/main/config/nullmailer.nix
lib for reuse in config: https://github.com/lilyinstarlight/foosteros/blob/main/modules/nixos/hardware/tkey.nix
adb: https://github.com/lilyinstarlight/foosteros/blob/main/config/adb.nix
environment variable: https://github.com/lilyinstarlight/foosteros/blob/main/config/base.nix#L133
home bin in path: https://github.com/lilyinstarlight/foosteros/blob/main/config/base.nix#L138
htop config: https://github.com/lilyinstarlight/foosteros/blob/main/config/base.nix#L199C1-L204C5
systemd out of memery : https://github.com/lilyinstarlight/foosteros/blob/main/config/base.nix#L199C1-L204C5
store gc: https://github.com/lilyinstarlight/foosteros/blob/main/config/gc.nix
intel https://github.com/lilyinstarlight/foosteros/blob/main/config/intelgfx.nix
support home manager config along system: https://github.com/reckenrode/nixos-configs/blob/main/flake.nix
mac config: https://github.com/reckenrode/nixos-configs/
envfs: https://github.com/canadaduane/my-nixos-conf/blob/main/system/envfs.nix
firefox setup: https://github.com/canadaduane/my-nixos-conf/blob/main/system/firefox.nix
flatpak: https://github.com/canadaduane/my-nixos-conf/blob/main/system/flatpak.nix
font: https://github.com/canadaduane/my-nixos-conf/blob/main/system/fonts.nix
firmware: https://github.com/canadaduane/my-nixos-conf/blob/main/system/hardware.nix
generic user: https://github.com/canadaduane/my-nixos-conf/blob/main/system/users.nix
example generic package for hasicorp: https://github.com/mitchellh/nixos-config/blob/main/pkgs/hashicorp/generic.nix
htop: https://github.com/jonringer/nixpkgs-config/blob/6ff7a9291a56e7246ebb21b1477dd3e9830d6098/home.nix#L12

machines from folder: https://github.com/chvp/nixos-config/blob/main/flake.nix
        https://github.com/axelf4/nixos-config/blob/master/flake.nix
dynamic import modules: https://github.com/reckenrode/nixos-configs/blob/main/flake.nix
building a package and install based on packages: https://github.com/axelf4/nixos-config/blob/master/packages/conan.nix
factorize machines: https://www.reddit.com/r/NixOS/comments/16cssv9/simple_steps_to_build_a_multimachine_flake_for_3/
nix complex config with install anywhere: https://github.com/ironman820/flake/blob/main/install.sh
steam: https://github.com/ChrisTitusTech/nixos-titus/blob/main/system/configuration.nix
gtk config: https://discourse.nixos.org/t/lightdm-dwm-issues/32661
epita infra: https://gitlab.cri.epita.fr/cri/infrastructure/nixpie/-/blob/master/images/default.nix?ref_type=heads
systemctl --failed --user
modules declared in a single place: https://github.com/ironman820/flake/blob/main/homes/x86_64-linux/modules.nix
secureboot: https://git.sr.ht/~mchrist/dotfiles/tree/master/item/nixos/modules/secureboot.nix
https://github.com/kamadorueda/machine/blob/9e71899d5f8a9c38229092483f4328dc173a4b22/nixos-modules/well-known/default.nix


# import lib from path:
```nix
{mylib, ...}: {
  imports = mylib.scanPaths ./.;
}
```

https://github.com/canadaduane/my-nixos-conf/blob/main/system/shells.nix
https://github.com/axelf4/nixos-config/blob/master/flake.nix
https://github.com/ironman820/flake/blob/main/modules/nixos/suites/workstation/default.nix
https://codeberg.org/PopeRigby/nixos/src/branch/main/systems/x86_64-iso/skut/default.nix
https://github.com/danth/stylix
https://github.com/khaneliman/khanelinix/blob/main/flake.nix
https://git.hoyer.xyz/harald/nixcfg/src/branch/main
