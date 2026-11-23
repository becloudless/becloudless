{ config, lib, ... }:
{
  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "edge" ]; }
    (lib.mkIf (config.bcl.role.name == "edge") {
      # A plain VPS of a provider that is the entry point of a cluster from the internet, with no cluster of its own: the service is the
      # module `bcl.edge` (set its options), the role is the host around it.
      bcl.edge.enable = true;

      bcl.role.setAdminPassword = true; # being able to log in to console
      security.sudo.wheelNeedsPassword = false;

      # a node on the internet has its disk encrypted (unlocked through the SSH of the initrd)
      bcl.diskSystem.encrypted = lib.mkDefault true;
      bcl.boot.ssh = true;

      services.resolved.settings.Resolve.DNSSEC = "true";

      # the address comes from the DHCP of the provider (and its IPv6 router advertisements) on the interface, without bridge (the provider only
      # knows the MAC of the NIC)
      systemd.network.enable = true;
      systemd.network.networks.net = {
        matchConfig.Name = config.bcl.network.interface;
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
          IgnoreCarrierLoss = true;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # `bcl.edge` opens its ports, SSH is opened by the OpenSSH service
      networking.firewall.enable = true;

      environment.persistence."/nix".hideMounts = true;
    })
  ];
}
