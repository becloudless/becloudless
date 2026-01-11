{
  bcl.global = {
    enable = true;
    timeZone = "Europe/Berlin";
    name = "bcl-test";
    domain = "bcl.test";
    git = {
      publicKey = "ssh-rsa something";
    };
    secretFile = ./default.secrets.yaml;
    admin = {
      users = {
        toto = {
          sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKLfbnSz9WNijTILw0ub93dHJ1bOxUH/MpoH2kiPWfiJ";
        };
      };
    };
  };
}
