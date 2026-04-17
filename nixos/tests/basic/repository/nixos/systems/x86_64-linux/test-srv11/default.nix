{
  bcl = {
    system = {
      enable = true;
      hardware = "qemu-x86_64";
      group = "test-server";
      ids = "motherboardUuid=11111111-1111-1111-1111-111111111111";
      devices = [ "/dev/sda" ];
    };
  };
}
