{
  bcl.global = {
    enable = true;
    timeZone = "Europe/Berlin";
    admin = {
      passwordSecretFile = ./default.secrets.yaml;
      users = {
        toto = {
          sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKLfbnSz9WNijTILw0ub93dHJ1bOxUH/MpoH2kiPWfiJ";
        };
      };
    };
  };
}