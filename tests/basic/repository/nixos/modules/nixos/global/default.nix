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
        n0rad = {
          sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvM8t4hXJxjBzrUS5FhAQ/TD9TJscT7CyLKFSOjZjj4";
        };
      };
    };
    networking.wireless = {
      "SSID1" = {};
      "SSID2" = {};
    };
  };
}
