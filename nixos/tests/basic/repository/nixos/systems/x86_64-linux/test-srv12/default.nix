{
  bcl = {
    system = {
      enable = true;
      hardware = "qemu-x86_64";
      group = "test-server";
      ids = "motherboardUuid=22222222-2222-2222-2222-222222222222";
      devices = [ "/dev/sda" ];
    };
  };
}
