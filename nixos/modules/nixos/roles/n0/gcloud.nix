{ config, lib, pkgs, ... }:
let
  gdk = pkgs.google-cloud-sdk.withExtraComponents( with pkgs.google-cloud-sdk.components; [
    gke-gcloud-auth-plugin
  ]);
in
{
  config = lib.mkIf (config.bcl.role.name == "n0") {
    environment.systemPackages = with pkgs; [
      gdk
    ];
  };
}
