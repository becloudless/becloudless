{
    lib,
    inputs,
    namespace,
    pkgs,
    mkShell,
    ...
}:

# mkdir kernel
# cd kernel
# git init
# git remote add origin https://github.com/Joshua-Riek/linux-rockchip.git
# git fetch --depth 1 origin e21cf49ee9a41a02846da050a6930e317bc99b68
# git checkout FETCH_HEAD


mkShell {
    packages = with pkgs; [
      qemu_kvm
      qemu-utils
    ];

    overlays = [
      pkgs.nixos-anywhere
    ];

    shellHook = ''
      '';
}
