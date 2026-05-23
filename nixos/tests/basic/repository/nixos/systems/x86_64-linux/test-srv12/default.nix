{
  bcl = {
    system = {
      enable = true;
      hardware = "qemu-x86_64";
      group = "test-server";
      id.motherboardUuid = "22222222-2222-2222-2222-222222222222";
      devices = [ "/dev/sda" ];
    };

    disks = {
      ssd1 = {
        devices = ["/dev/disks/by-id/xxx" "/dev/disks/by-id/yyy"];
      };
    };

  };
}
