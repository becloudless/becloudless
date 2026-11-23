{ config, lib, ... }:
let
  cfg = config.bcl.role.kube;
  edge = cfg.pop.edge;
  ifName = "wg-edge";

  # `acl <name> <fetch> ...` lines for names: exact (`app.example.com`) or a suffix when it starts with a dot (`.example.com`)
  acl = name: fetch: names: lib.concatMapStringsSep "\n" (
    n: "acl ${name} ${fetch} -i -m ${if lib.hasPrefix "." n then "end" else "str"} ${n}"
  ) names;

  hasLocal = edge.local.hostnames != [ ];
  hasLocalBackend = edge.local.address != null;
  hostHeader = "req.hdr(host),field(1,:)";

  upstreamServer = port: "server upstream ${edge.upstream.address}:${toString port} send-proxy-v2 source ${edge.address}";

  # the public ports listen on IPv4 and IPv6
  bind = port: "bind :::${toString port} v4v6";
in
{
  options.bcl.role.kube.pop.edge = {
    enable = lib.mkEnableOption ''
      the node as an entry point of another cluster, through a WireGuard tunnel that the other cluster dials (like a Cloudflare Tunnel, no
      router in the path). The haproxy of the node owns the ports 80 and 443 (the names of `local.hostnames` and the apiserver stay on
      the node, every other name is sent through the tunnel) and sends the address of the client with the PROXY protocol, the Gateway of
      the other cluster sees it. Several nodes can do it for the same cluster (one DNS record each): each has its own tunnel `address`.
      The private key of the tunnel is generated on the node at its first start (`wg show ${ifName} public-key` gives the public key to
      declare on the other side)
    '';

    address = lib.mkOption {
      type = lib.types.str;
      example = "10.99.0.1";
      description = "Address of this node in the tunnel network (one per node, the same network for the nodes and the other cluster).";
    };

    prefixLength = lib.mkOption {
      type = lib.types.ints.between 8 30;
      default = 24;
      description = "Prefix length of the tunnel network.";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "UDP port of the tunnel, the other cluster dials it on the public address of the node.";
    };

    upstream = {
      address = lib.mkOption {
        type = lib.types.str;
        example = "10.99.0.254";
        description = "Address in the tunnel network of the entry point of the other cluster, where the requests are sent.";
      };

      publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "WireGuard public key of the other cluster. Without it the tunnel has no peer yet (the node still generates its own key).";
      };

      httpPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port of the entry point of the other cluster for the HTTP requests (with the PROXY protocol).";
      };

      httpsPort = lib.mkOption {
        type = lib.types.port;
        default = 8443;
        description = "Port of the entry point of the other cluster for the TLS connections (with the PROXY protocol).";
      };

      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        example = [ 25 465 993 ];
        description = ''
          TCP ports opened to everybody and forwarded as they are (with the PROXY protocol, the address of the client in its header) to
          the entry point of the other cluster, on the port `tcpPortOffset` + the port (the mail ports of the cluster).
        '';
      };

      tcpPortOffset = lib.mkOption {
        type = lib.types.ints.between 1 60000;
        default = 10000;
        description = "Added to a port of `tcpPorts` to get the port of the entry point of the other cluster.";
      };
    };

    relay = {
      enable = lib.mkEnableOption ''
        the relay of the outgoing mails of the other cluster: a Postfix that only listens on the tunnel address (port `relay.port`) and
        delivers the mails from the address of the node, the one of its reverse DNS and of the SPF record of the domains. The other
        cluster sends its mails to it through the tunnel (its mail server has no direct access to the port 25 of the internet)
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

    local = {
      hostnames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "mail.example.com" ".pop.example.com" ];
        description = ''
          Names served by the cluster of this node, not sent through the tunnel: a name (`app.example.com`) or a suffix when it starts
          with a dot (`.example.com`). The name of the apiserver is always kept on the node.
        '';
      };

      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Address (the LoadBalancer IP of the Gateway of this cluster) that gets the ports 80 and 443 of the names of
          `local.hostnames`. Without it the node serves nothing itself: these names are refused.
        '';
      };

    };
  };

  config = lib.mkIf (config.bcl.role.name == "kube" && cfg.pop.enable && edge.enable) {
    assertions = [
      {
        assertion = !hasLocal || hasLocalBackend;
        message = "bcl.role.kube.pop.edge.local.hostnames needs bcl.role.kube.pop.edge.local.address";
      }
    ];

    networking.wireguard.interfaces.${ifName} = {
      ips = [ "${edge.address}/${toString edge.prefixLength}" ];
      listenPort = edge.listenPort;
      mtu = 1380; # the tunnel runs over the pod network of the other cluster (vxlan)
      privateKeyFile = "/var/lib/wireguard/${ifName}.key";
      generatePrivateKeyFile = true;
      peers = lib.optional (edge.upstream.publicKey != null) {
        publicKey = edge.upstream.publicKey;
        allowedIPs = [ "${edge.upstream.address}/32" ];
      };
    };

    networking.firewall.allowedUDPPorts = [ edge.listenPort ];
    networking.firewall.allowedTCPPorts = edge.upstream.tcpPorts;
    networking.firewall.interfaces.${ifName}.allowedTCPPorts = lib.optional edge.relay.enable edge.relay.port;

    # the root is a tmpfs: the key identifies the node on the other side, it has to outlive the reboots; the queue of the relay holds the mails
    # it accepted and did not deliver yet
    environment.persistence."/nix".directories = [
      { directory = "/var/lib/wireguard"; mode = "u=rwx,g=,o="; }
    ] ++ lib.optional edge.relay.enable { directory = "/var/lib/postfix"; };

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

        # TLS: routed by the SNI, the connection is forwarded as it is (the certificates are the ones of the clusters)
        frontend https
          ${bind 443}
          tcp-request inspect-delay 5s
          tcp-request content accept if { req.ssl_hello_type 1 }
          acl apiserver req.ssl_sni -i -m str ${cfg.apiServerName}
          ${lib.optionalString hasLocal (acl "local" "req.ssl_sni" edge.local.hostnames)}
          use_backend apiserver if apiserver
          ${lib.optionalString hasLocal "use_backend local-https if local"}
          default_backend upstream-https

        backend apiserver
          server apiserver 127.0.0.1:6443

        backend upstream-https
          ${upstreamServer edge.upstream.httpsPort}

        ${lib.optionalString hasLocalBackend ''
        backend local-https
          server local ${edge.local.address}:443
        ''}

        # HTTP: routed by the Host header
        frontend http
          ${bind 80}
          mode http
          ${lib.optionalString hasLocal (acl "local" hostHeader edge.local.hostnames)}
          ${lib.optionalString hasLocal "use_backend local-http if local"}
          default_backend upstream-http

        backend upstream-http
          mode http
          # a connection carries the address of one client in its PROXY header: never shared
          http-reuse never
          ${upstreamServer edge.upstream.httpPort}

        ${lib.optionalString hasLocalBackend ''
        backend local-http
          mode http
          server local ${edge.local.address}:80
        ''}

        # TCP (mail): forwarded to the other cluster, which reads the PROXY header of its mail server
        ${lib.concatMapStringsSep "\n" (port: ''
        frontend tcp-${toString port}
          ${bind port}
          default_backend upstream-tcp-${toString port}

        backend upstream-tcp-${toString port}
          ${upstreamServer (port + edge.upstream.tcpPortOffset)}
        '') edge.upstream.tcpPorts}
      '';
    };

    # `source`: the connections to the other cluster leave with the address of the tunnel, the only one its peer accepts
    systemd.services.haproxy = {
      after = [ "wireguard-${ifName}.service" ];
      wants = [ "wireguard-${ifName}.service" ];
    };

    # The relay of the outgoing mails: only the other cluster (the address of its entry point in the tunnel) can use it, nothing is delivered
    # locally, the mails leave from the address of the node.
    services.postfix = lib.mkIf edge.relay.enable {
      enable = true;
      settings.main = {
        myhostname = edge.relay.hostname;
        inet_interfaces = "loopback-only";
        inet_protocols = "ipv4";
        mydestination = [ ];
        mynetworks = [ "${edge.upstream.address}/32" ];
        smtpd_relay_restrictions = "permit_mynetworks, reject";
        smtp_tls_security_level = "may";
        smtp_helo_name = "$myhostname";
      };
      # the smtpd of the master.cf listens on the tunnel address and the port of the relay, not on the port 25 of every address (the
      # haproxy has it)
      settings.master.smtp_inet.name = lib.mkForce "${edge.address}:${toString edge.relay.port}";
    };

    systemd.services.postfix = lib.mkIf edge.relay.enable {
      after = [ "wireguard-${ifName}.service" ];
      wants = [ "wireguard-${ifName}.service" ];
    };
  };
}
