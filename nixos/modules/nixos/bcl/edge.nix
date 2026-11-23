{ config, lib, ... }:
let
  cfg = config.bcl.edge;
  ifName = "wg-edge";

  upstreamServer = port: "server upstream ${cfg.upstream.address}:${toString port} send-proxy-v2 source ${cfg.address}";

  # the public ports listen on IPv4 and IPv6
  bind = port: "bind :::${toString port} v4v6";
in
{
  options.bcl.edge = {
    enable = lib.mkEnableOption ''
      the node as an entry point of a cluster from the internet (like a Cloudflare Tunnel, no router in the path): a WireGuard tunnel that
      the cluster dials, and a haproxy that owns the ports 80 and 443 (every name goes through the tunnel, TLS and HTTP as they are) and
      sends the address of the client with the PROXY protocol, so the Gateway of the cluster sees it. Several nodes can do it for the same
      cluster (one DNS record each): each has its own tunnel `address`. The private key of the tunnel is generated on the node at its first
      start (`wg show ${ifName} public-key` gives the public key to declare on the cluster).

      This is only the service: the network, the firewall (it has to be enabled, the module opens its ports) and the disk of the node are
      the business of the host, see the role `edge` for a plain VPS. The ports 80 and 443 must be free (not the ones of a Gateway running
      with `hostNetwork`)
    '';

    address = lib.mkOption {
      type = lib.types.str;
      example = "10.99.0.1";
      description = "Address of this node in the tunnel network (one per node, the same network for the nodes and the cluster).";
    };

    prefixLength = lib.mkOption {
      type = lib.types.ints.between 8 30;
      default = 24;
      description = "Prefix length of the tunnel network.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "UDP port of the tunnel, the cluster dials it on the public address of the node.";
    };

    upstream = {
      address = lib.mkOption {
        type = lib.types.str;
        example = "10.99.0.254";
        description = "Address in the tunnel network of the entry point of the cluster, where the requests are sent.";
      };

      publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "WireGuard public key of the cluster. Without it the tunnel has no peer yet (the node still generates its own key).";
      };

      httpPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port of the entry point of the cluster for the HTTP requests (with the PROXY protocol).";
      };

      httpsPort = lib.mkOption {
        type = lib.types.port;
        default = 8443;
        description = "Port of the entry point of the cluster for the TLS connections (with the PROXY protocol).";
      };

      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        example = [ 25 465 993 ];
        description = ''
          TCP ports opened to everybody and forwarded as they are (with the PROXY protocol, the address of the client in its header) to
          the entry point of the cluster, on the port `tcpPortOffset` + the port (the mail ports of the cluster).
        '';
      };

      tcpPortOffset = lib.mkOption {
        type = lib.types.ints.between 1 60000;
        default = 10000;
        description = "Added to a port of `tcpPorts` to get the port of the entry point of the cluster.";
      };
    };

    relay = {
      enable = lib.mkEnableOption ''
        the relay of the outgoing mails of the cluster: a Postfix that only listens on the tunnel address (port `relay.port`) and
        delivers the mails from the address of the node, the one of its reverse DNS and of the SPF record of the domains. The cluster
        sends its mails to it through the tunnel (its mail server has no direct access to the port 25 of the internet)
      '';

      hostname = lib.mkOption {
        type = lib.types.str;
        example = "pop1.example.com";
        description = "Name the relay introduces itself with (HELO): the reverse DNS of the public address of the node must be this name.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 2525;
        description = "TCP port of the relay on the tunnel address.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    networking.wireguard.interfaces.${ifName} = {
      ips = [ "${cfg.address}/${toString cfg.prefixLength}" ];
      listenPort = cfg.listenPort;
      mtu = 1380; # the tunnel runs over the pod network of the cluster (vxlan)
      privateKeyFile = "/var/lib/wireguard/${ifName}.key";
      generatePrivateKeyFile = true;
      peers = lib.optional (cfg.upstream.publicKey != null) {
        publicKey = cfg.upstream.publicKey;
        allowedIPs = [ "${cfg.upstream.address}/32" ];
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ 80 443 ] ++ cfg.upstream.tcpPorts;
      allowedUDPPorts = [ cfg.listenPort ];
      interfaces.${ifName}.allowedTCPPorts = lib.optional cfg.relay.enable cfg.relay.port;
    };

    # the root is a tmpfs: the key identifies the node on the cluster side, it has to outlive the reboots; the queue of the relay holds the mails
    # it accepted and did not deliver yet
    environment.persistence."/nix".directories = [
      { directory = "/var/lib/wireguard"; mode = "u=rwx,g=,o="; }
    ] ++ lib.optional cfg.relay.enable { directory = "/var/lib/postfix"; };

    services.haproxy = {
      enable = true;
      config = ''
        defaults
          mode tcp
          timeout connect 10s
          timeout client 1h
          timeout server 1h
          timeout tunnel 1h
          timeout http-request 10s

        # TLS: forwarded as it is (the certificates are the ones of the cluster)
        frontend https
          ${bind 443}
          default_backend upstream-https

        backend upstream-https
          ${upstreamServer cfg.upstream.httpsPort}

        frontend http
          ${bind 80}
          mode http
          default_backend upstream-http

        backend upstream-http
          mode http
          # a connection carries the address of one client in its PROXY header: never shared
          http-reuse never
          ${upstreamServer cfg.upstream.httpPort}

        # TCP (mail): forwarded to the cluster, which reads the PROXY header of its mail server
        ${lib.concatMapStringsSep "\n" (port: ''
        frontend tcp-${toString port}
          ${bind port}
          default_backend upstream-tcp-${toString port}

        backend upstream-tcp-${toString port}
          ${upstreamServer (port + cfg.upstream.tcpPortOffset)}
        '') cfg.upstream.tcpPorts}
      '';
    };

    # `source`: the connections to the cluster leave with the address of the tunnel, the only one its peer accepts
    systemd.services.haproxy = {
      after = [ "wireguard-${ifName}.service" ];
      wants = [ "wireguard-${ifName}.service" ];
    };

    # The relay of the outgoing mails: only the cluster (the address of its entry point in the tunnel) can use it, nothing is delivered
    # locally, the mails leave from the address of the node.
    services.postfix = lib.mkIf cfg.relay.enable {
      enable = true;
      settings.main = {
        myhostname = cfg.relay.hostname;
        inet_interfaces = "loopback-only";
        inet_protocols = "ipv4";
        mydestination = [ ];
        mynetworks = [ "${cfg.upstream.address}/32" ];
        smtpd_relay_restrictions = "permit_mynetworks, reject";
        smtp_tls_security_level = "may";
        smtp_helo_name = "$myhostname";
      };
      # the smtpd of the master.cf listens on the tunnel address and the port of the relay, not on the port 25 of every address (the
      # haproxy has it)
      settings.master.smtp_inet.name = lib.mkForce "${cfg.address}:${toString cfg.relay.port}";
    };

    systemd.services.postfix = lib.mkIf cfg.relay.enable {
      after = [ "wireguard-${ifName}.service" ];
      wants = [ "wireguard-${ifName}.service" ];
    };
  };
}
