{config, lib, ...}:
{
  config = lib.mkIf (config.bcl.group.name == "test-workstation") {
    bcl.role.name = "workstation";
    bcl.role.secretFile = ./default.secrets.yaml;

    bcl.boot.initrdSSHPrivateKey = ''
      -----BEGIN OPENSSH PRIVATE KEY-----
      dummy
      -----END OPENSSH PRIVATE KEY-----
    '';

  };
}