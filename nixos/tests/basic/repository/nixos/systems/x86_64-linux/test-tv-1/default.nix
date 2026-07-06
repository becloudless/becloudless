{
  bcl = {
    system = {
      enable = true;
      hardware = "qemu-x86_64";
      group = "test-tv";
      id.motherboardUuid = "7d5e9855-0cba-4c41-b45e-cdff7a9514d9";
      devices = [ "/dev/sda" ];
    };
  };
  bcl.role.tv.disableGpuCompositing = true;
  bcl.role.tv.forceSoftwareGL = true;
}
