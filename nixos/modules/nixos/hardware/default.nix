{ config, lib, ... }:

{
  options.bcl.hardware = {
    device = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Hardware device identifier. Must match one of the registered knownDevices.";
    };
    knownDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of valid device identifiers. Each device module registers itself here.";
    };
    commons = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };

  config = lib.mkIf (config.bcl.hardware.device != "") {
    assertions = [
      {
        assertion = builtins.elem config.bcl.hardware.device config.bcl.hardware.knownDevices;
        message = ''
          bcl.hardware.device is set to "${config.bcl.hardware.device}" which is not a known device.
          Known devices: ${lib.concatStringsSep ", " config.bcl.hardware.knownDevices}
          Make sure the corresponding device module is imported.
        '';
      }
    ];
  };
}
