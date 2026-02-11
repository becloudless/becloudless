{config, lib, ...}:
{
  config = lib.mkIf (config.bcl.group.name == "test-server") {
    bcl.role.name = "serverKube";
    bcl.role.serverKube = {
      clusterName = "test";
      clusterNumber = 1;
      clusterSize = 2;  # test-srv11 and test-srv12
    };
    bcl.role.secretFile = ./default.secrets.yaml;

    bcl.boot.initrdSSHPrivateKey = ''
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
      QyNTUxOQAAACCoZb7aDq3AO3uM6o74iCwqAW49kp0Y/85P/jMxOg4KgAAAAJDfGN0k3xjd
      JAAAAAtzc2gtZWQyNTUxOQAAACCoZb7aDq3AO3uM6o74iCwqAW49kp0Y/85P/jMxOg4KgA
      AAAEBMSEXe/kgbeU5BHQW5ZLiTsOurPF1xx84gEcEgrwzvTKhlvtoOrcA7e4zqjviILCoB
      bj2SnRj/zk/+MzE6DgqAAAAACm4wcmFkQG4wbDIBAgM=
      -----END OPENSSH PRIVATE KEY-----
    '';
  };
}



