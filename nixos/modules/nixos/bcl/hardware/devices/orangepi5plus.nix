{ inputs, config, lib, pkgs, ... }:
{
  config = lib.mkMerge [
    { bcl.hardware.knownDevices = [ "orangepi5plus" ]; }
    (lib.mkIf (config.bcl.hardware.device == "orangepi5plus") {
    bcl.hardware.commons = [ "orangepi5" ];

    bcl.diskSystem.ubootPackage = lib.mkIf (config.bcl.boot.loader == "uboot") pkgs.ubootOrangePi5Plus;

    hardware.deviceTree = {
      name = "rockchip/rk3588-orangepi-5-plus.dtb";
    };

    # Both network cards are enabled and cannot be disabled, we have to be explicit
    systemd.network.networks.net.matchConfig = {
      Name = lib.mkForce "enP3p49s0"; # next to power. enP4p65s0 next to hdmi
    };

    boot.initrd = {
      # Load the DRM/HDMI stack in initrd too, so the HDMI video console
      # (tty1) actually works during initrd (previously blank/inactive,
      # since these are loadable modules not builtin, and NixOS only loads
      # `availableKernelModules` opportunistically via udev - HDMI has no
      # udev-visible "add" event to trigger it, unlike PCI/USB devices).
      #
      # phy_rockchip_naneng_combphy is the REAL fix for the onboard r8169
      # NICs not coming up during initrd (previously misdiagnosed as a
      # PHY-sharing/timing race -- it is not). The two NICs' PCIe root
      # complexes (a40c00000.pcie / a41000000.pcie) depend on this combo
      # PHY driver, which is a loadable module, not builtin. Modules not
      # copied into the initrd image do not exist there at all, so udev's
      # "add" event for the PCIe device can't modprobe it, `phy_get()`
      # fails, and the probe permanently defers with "failed to initialize
      # the phy" -- confirmed via `lsmod` showing
      # `phy_rockchip_naneng_combphy` bound to exactly the PHY instances
      # feeding these PCIe controllers, and the module not being present in
      # `boot.initrd.availableKernelModules` before this change. (The third
      # PCIe root complex, a40000000.pcie, was never affected because it
      # doesn't go through this combo PHY.)
      kernelModules = [ "r8169" "phy_rockchip_samsung_hdptx" "rockchipdrm" "phy_rockchip_naneng_combphy" ]; # support network + video at boot
      availableKernelModules = [
        "usbhid"
        "r8169"
        "phy_rockchip_samsung_hdptx"
        "dw_hdmi_qp"
        "rockchipdrm"
        "phy_rockchip_naneng_combphy"
      ];
    };
  })
  ];
}
