{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.bcl.role.name != "") {

    services.getty.helpLine = lib.mkForce "" ;
    services.getty.greetingLine = ''<<< bcl ${config.system.nixos.label} (\m) - \l >>>'';

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    # Without this, `nixos-rebuild switch --target-host` (which copies a
    # locally-built, UNSIGNED closure via nix-copy-closure over the admin
    # user's own SSH login, not root) fails outright on any host with the
    # default `trusted-users = [ "root" ]`: the remote nix-daemon rejects
    # every path with "lacks a signature by a trusted key" (confirmed live
    # on salon-0 - a `nixos-rebuild switch --target-host` attempt silently
    # produced NO deployed changes for several iterations before this was
    # noticed, since nixos-rebuild's own summary line only reports the
    # generic "returned non-zero exit status 1" from nix-copy-closure).
    # `@wheel` (rather than a specific username) covers whichever admin
    # user happens to SSH in as, consistent across all hosts.
    nix.settings.trusted-users = [ "root" "@wheel" ];

  };
}
