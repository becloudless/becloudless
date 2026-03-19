{config, lib, ...}:
{
  config = lib.mkIf (config.bcl.group.name == "test-workstation") {
    bcl.role.name = "workstation";
    bcl.role.secretFile = ./default.secrets.yaml;
    bcl.users.auser = {
      sopsFile = ./default.secrets.yaml;
      wm = "gnome";
    };

    bcl.boot.initrdSSHPrivateKey = ''
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
      QyNTUxOQAAACBsCD9jL4J2Fg9B5CoE7MIXIawRtYPHpYWV0gCVnOnyqAAAAJDyw8FM8sPB
      TAAAAAtzc2gtZWQyNTUxOQAAACBsCD9jL4J2Fg9B5CoE7MIXIawRtYPHpYWV0gCVnOnyqA
      AAAED5YT+RE4eU6K+n6ztTFhgNF/NSeXePOhWS4TE4vUeLyWwIP2MvgnYWD0HkKgTswhch
      rBG1g8elhZXSAJWc6fKoAAAACm4wcmFkQG4wbDIBAgM=
      -----END OPENSSH PRIVATE KEY-----
    '';

  };
}