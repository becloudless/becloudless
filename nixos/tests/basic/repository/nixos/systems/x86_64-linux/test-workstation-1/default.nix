{
  bcl = {
    boot = {
      # TODO check if still required
      ssh = true; # for testing only
    };
    system = {
      enable = true;
      hardware = "qemu-x86_64";
      group = "test-workstation";
      ids = "motherboardUuid=c9b0fb14-1949-6949-9711-63409d2f9cfe";
      devices = [ "/dev/sda" ];
    };
  };
}
