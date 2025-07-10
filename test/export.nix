let
  pkgs = import <nixpkgs> {};
  clan-core = builtins.getFlake "git+https://git.clan.lol/clan/clan-core";
  options = (pkgs.nixos {}).options.networking.domain;
in
  (clan-core.lib.jsonschema {}).parseOption options

