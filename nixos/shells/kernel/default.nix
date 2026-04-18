{
    lib,
    inputs,
    namespace,
    pkgs,
    mkShell,
    ...
}:

# nix develop .#kernel
# mkdir ~/kernel
# cd ~/kernel
# git init
# git remote add origin https://github.com/Joshua-Riek/linux-rockchip.git
# git fetch --depth 1 origin e21cf49ee9a41a02846da050a6930e317bc99b68
# git checkout FETCH_HEAD
# cp /nix/bcl/becloudless/nixos/packages/orangepi-kernel/rk35xx_vendor_config .config
# make menuconfig
# make -j8

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