{
  bcl = {
    system = {
      enable = true;
      hardware = "qemu-x86_64";
      group = "test-server";
      ids = "motherboardUuid=22222222-2222-2222-2222-222222222222";
      devices = [ "/dev/sda" ];
    };

    disks = {
      ssd1 = {
        path=/disks/ssd1;
        encrypted = true;
        format = "btrfs";
        mode = "raid0";
        devices = ["/dev/disks/by-id/xxx" "/dev/disks/by-id/yyy"];
      };
    };

  };
}
