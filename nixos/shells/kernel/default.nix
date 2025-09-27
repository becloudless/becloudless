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
      qemu_kvm
      qemu-utils
    ];

    overlays = [
      pkgs.nixos-anywhere
    ];

    shellHook = ''
      '';
}
