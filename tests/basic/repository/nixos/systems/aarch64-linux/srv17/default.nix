{lib, ...}:
{

  bcl.hardware.device = "orangepi5plus";
  bcl.disk.encrypted = lib.mkForce false;
  bcl.system = {
    enable = true;
    group = "test-server";
    ids = "networkMacs=c0:74:2b:ff:5d:96,c0:74:2b:ff:5d:97";
    devices = [ "/dev/disk/by-id/nvme-CT4000P3SSD8_2312E6BF61B3" ];
  };

}
