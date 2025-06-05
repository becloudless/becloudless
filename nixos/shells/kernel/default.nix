{
    lib,
    inputs,
    namespace,
    pkgs,
    mkShell,
    ...
}:

mkShell {
    packages = with pkgs; [
      pkg-config
      ncurses
      gcc
      flex
      bison
      bc
      openssl
    ];

    shellHook = ''
        export DEBUG=1
      '';
}

# build phase by phase
# https://discourse.nixos.org/t/nix-build-phases-run-nix-build-phases-interactively/36090
# https://github.com/imincik/nix-utils/blob/5278ab4635672d0537f032d785f4e0bf1842f2e3/nix-build-phases.bash
