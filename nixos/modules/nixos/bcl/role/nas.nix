{ config, lib, pkgs, ... }:
let
  cfg = config.bcl.role.nas;
  isActive = config.bcl.role.name == "nas";
  isDc = cfg.ad.mode == "dc";

  # NetBIOS names (workgroup, machine name) must be uppercase ASCII, no dots,
  # max 15 chars.
  sanitizeNetbios = s:
    builtins.substring 0 15 (lib.toUpper (builtins.replaceStrings [ "." ] [ "-" ] s));

  fqdn = config.networking.fqdn;

  enabledShares = lib.filterAttrs (_: s: s.smb.enable) cfg.shares;
  nfsShares = lib.filterAttrs (_: s: s.nfs.enable) cfg.shares;
  anyNfsKrb5 = lib.any (s: s.nfs.enable && s.nfs.kerberos) (lib.attrValues cfg.shares);

  smbSharesSettings = lib.mapAttrs (_: s:
    {
      path = s.path;
      comment = s.comment;
      browseable = "yes";
      "read only" = if s.smb.readOnly then "yes" else "no";
      "guest ok" = if s.smb.guestOk then "yes" else "no";
    } // lib.optionalAttrs (s.smb.validUsers != [] || s.smb.validGroups != []) {
      "valid users" = s.smb.validUsers ++ map (g: "@${g}") s.smb.validGroups;
    }
  ) enabledShares;

  nfsExportLine = name: s:
    let
      mode = if s.nfs.readOnly then "ro" else "rw";
      sec = if s.nfs.kerberos then "sec=krb5p" else "sec=sys";
      clients = lib.concatMapStringsSep " " (c: "${c}(${mode},${sec},no_subtree_check)") s.nfs.allowedClients;
    in "${s.path} ${clients}";

  globalSettings =
    {
      "netbios name" = sanitizeNetbios config.networking.hostName;
      workgroup = cfg.ad.workgroup;
      realm = cfg.ad.realm;
    }
    // lib.optionalAttrs isDc (
      { "server role" = "active directory domain controller"; }
      // lib.optionalAttrs (cfg.ad.dnsForwarder != null) { "dns forwarder" = cfg.ad.dnsForwarder; }
    )
    // lib.optionalAttrs (!isDc) {
      security = "ads";
      "kerberos method" = "secrets and keytab";
      "winbind use default domain" = "yes";
      "winbind refresh tickets" = "yes";
      "template shell" = "/bin/bash";
      "template homedir" = "/home/%D/%U";
      "idmap config * : backend" = "tdb";
      "idmap config * : range" = "3000-7999";
      "idmap config ${cfg.ad.workgroup} : backend" = "rid";
      "idmap config ${cfg.ad.workgroup} : range" = "10000-999999";
    };
in {

  options.bcl.role.nas = {
    ad = {
      mode = lib.mkOption {
        type = lib.types.enum [ "dc" "member" ];
        default = "dc";
        description = ''
          Whether this host provisions and hosts a brand new Samba Active
          Directory domain ("dc"), or joins an already-existing AD domain as
          a plain member file server ("member").
        '';
      };
      realm = lib.mkOption {
        type = lib.types.str;
        default = lib.toUpper config.bcl.global.domain;
        defaultText = lib.literalExpression "lib.toUpper config.bcl.global.domain";
        description = "Kerberos/AD realm (e.g. \"EXAMPLE.COM\").";
      };
      domain = lib.mkOption {
        type = lib.types.str;
        default = config.bcl.global.domain;
        defaultText = lib.literalExpression "config.bcl.global.domain";
        description = "DNS domain of the AD forest (lowercase, e.g. \"example.com\").";
      };
      workgroup = lib.mkOption {
        type = lib.types.str;
        default = sanitizeNetbios config.bcl.global.name;
        defaultText = lib.literalExpression "sanitizeNetbios config.bcl.global.name";
        description = "NetBIOS/short domain name (max 15 chars, e.g. \"EXAMPLE\").";
      };
      dcAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Address (or hostname) of an existing domain controller to join.
          Required when `mode` is "member".
        '';
      };
      joinAccount = lib.mkOption {
        type = lib.types.str;
        default = "Administrator";
        description = "AD account used to join the domain when `mode` is \"member\".";
      };
      dnsForwarder = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Recursive DNS forwarder for Samba's internal DNS server (\"dc\" mode only).";
      };
    };

    shares = lib.mkOption {
      default = {};
      description = "Folders exported over SMB and/or NFS.";
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.path;
            description = "Folder to export.";
          };
          comment = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Comment shown to SMB clients.";
          };
          smb = {
            enable = lib.mkOption { type = lib.types.bool; default = true; description = "Export this folder over SMB."; };
            readOnly = lib.mkOption { type = lib.types.bool; default = false; description = "Read-only SMB share."; };
            guestOk = lib.mkOption { type = lib.types.bool; default = false; description = "Allow guest (unauthenticated) SMB access."; };
            validUsers = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "AD users allowed access (e.g. \"DOMAIN\\\\alice\")."; };
            validGroups = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "AD groups allowed access (e.g. \"DOMAIN\\\\staff\")."; };
          };
          nfs = {
            enable = lib.mkOption { type = lib.types.bool; default = true; description = "Export this folder over NFS."; };
            readOnly = lib.mkOption { type = lib.types.bool; default = false; description = "Read-only NFS export."; };
            kerberos = lib.mkOption { type = lib.types.bool; default = true; description = "Require Kerberos (sec=krb5p) instead of AUTH_SYS for this NFS export."; };
            allowedClients = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "*" ]; description = "Client hosts/CIDR patterns allowed for this NFS export."; };
          };
        };
      });
    };
  };

  config = lib.mkMerge [
    { bcl.role.knownRoles = [ "nas" ]; }
    (lib.mkIf isActive {
      assertions = [
        {
          assertion = cfg.ad.mode == "dc" || cfg.ad.dcAddress != null;
          message = "bcl.role.nas.ad.dcAddress must be set when bcl.role.nas.ad.mode is \"member\".";
        }
      ];

      security.sudo.wheelNeedsPassword = false;

      # Kerberos realm/domain so kinit/klist and NFS's sec=krb5 work. Points at
      # ourselves when we are the DC, otherwise at the existing DC.
      security.krb5 = {
        enable = true;
        settings = {
          libdefaults = {
            default_realm = cfg.ad.realm;
            dns_lookup_kdc = true;
            dns_lookup_realm = false;
          };
          realms.${cfg.ad.realm} =
            if isDc
            then { kdc = "127.0.0.1"; admin_server = "127.0.0.1"; }
            else { kdc = cfg.ad.dcAddress; admin_server = cfg.ad.dcAddress; };
          domain_realm = {
            ${lib.toLower cfg.ad.domain} = cfg.ad.realm;
            ".${lib.toLower cfg.ad.domain}" = cfg.ad.realm;
          };
        };
      };

      # So config.networking.fqdn resolves and NFSv4 idmapd's "Domain" setting
      # (nixpkgs/nixos/modules/tasks/filesystems/nfs.nix) matches the AD domain.
      networking.domain = lib.mkForce cfg.ad.domain;

      services.samba = {
        enable = true;
        package = pkgs.samba4Full; # needed for samba-tool / AD DC support
        # The unified "samba" AD DC binary (started by our own
        # samba-ad-dc.service below) replaces smbd/nmbd/winbindd entirely -
        # running them alongside it would just fight over the same ports.
        smbd.enable = lib.mkForce (!isDc);
        nmbd.enable = lib.mkForce (!isDc);
        winbindd.enable = lib.mkForce (!isDc);
        settings = lib.mkMerge [ { global = globalSettings; } smbSharesSettings ];
      };

      # winbind's NSS module lets AD users/groups resolve as normal Unix
      # users/groups (needed for "valid users"/ACLs to work as expected).
      system.nssModules = lib.mkIf (!isDc) [ config.services.samba.package ];
      system.nssDatabases.passwd = lib.mkIf (!isDc) (lib.mkAfter [ "winbind" ]);
      system.nssDatabases.group = lib.mkIf (!isDc) (lib.mkAfter [ "winbind" ]);

      services.nfs.server = lib.mkIf (nfsShares != {}) {
        enable = true;
        createMountPoints = true;
        exports = lib.concatStringsSep "\n" (lib.mapAttrsToList nfsExportLine nfsShares);
        # Fixed ports so the firewall rules below are meaningful.
        mountdPort = 4002;
        lockdPort = 4001;
        statdPort = 4000;
      };

      # rpc-gssd/rpc-svcgssd (packaged with nfs-utils, see
      # nixos/modules/tasks/filesystems/nfs.nix) aren't started by default -
      # required for any sec=krb5* NFS export/mount to actually work.
      systemd.services.rpc-gssd.wantedBy = lib.mkIf anyNfsKrb5 [ "multi-user.target" ];
      systemd.services.rpc-svcgssd.wantedBy = lib.mkIf anyNfsKrb5 [ "multi-user.target" ];

      systemd.tmpfiles.rules = map (s: "d '${s.path}' 0755 root root - -") (lib.attrValues cfg.shares);

      # Idempotent AD domain provisioning (dc mode). Guarded on sam.ldb so a
      # redeploy/reboot never re-provisions. Uses its own throwaway
      # --configfile since /etc/samba/smb.conf is a read-only nix-store
      # symlink managed by services.samba above - the real runtime config
      # comes from services.samba.settings, not from this provisioning run.
      systemd.services.samba-ad-provision = lib.mkIf isDc {
        description = "Provision the Samba Active Directory domain";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        before = [ "samba-ad-dc.service" ];
        wantedBy = [ "multi-user.target" ];
        unitConfig.RequiresMountsFor = "/var/lib/samba";
        path = [ config.services.samba.package ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
        script = ''
          set -euo pipefail
          if [ -f /var/lib/samba/private/sam.ldb ]; then
            echo "Samba AD domain already provisioned, skipping."
            exit 0
          fi
          adminPassword="$(cat ${config.sops.secrets."nas.ad.password".path})"
          samba-tool domain provision \
            --server-role=dc \
            --use-rfc2307 \
            --dns-backend=SAMBA_INTERNAL \
            --realm="${cfg.ad.realm}" \
            --domain="${cfg.ad.workgroup}" \
            --adminpass="$adminPassword" \
            --configfile=/var/lib/samba/private/provision-smb.conf \
            ${lib.optionalString (cfg.ad.dnsForwarder != null) "--option=\"dns forwarder=${cfg.ad.dnsForwarder}\""}
        '';
      };

      # Unified AD DC daemon (replaces smbd/nmbd/winbindd, see comment above).
      systemd.services.samba-ad-dc = lib.mkIf isDc {
        description = "Samba Active Directory Domain Controller";
        after = [ "network.target" "network-online.target" "samba-ad-provision.service" ];
        requires = [ "samba-ad-provision.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        unitConfig.RequiresMountsFor = "/var/lib/samba";
        serviceConfig = {
          ExecStart = "${config.services.samba.package}/sbin/samba --foreground --no-process-group";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };

      # Idempotent domain join (member mode). smbd/nmbd/winbindd must start
      # after we actually have a machine account, otherwise they'd come up
      # broken on first boot.
      systemd.services.nas-ad-join = lib.mkIf (!isDc) {
        description = "Join this host to the Samba/Windows AD domain";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        before = [ "samba-smbd.service" "samba-nmbd.service" "samba-winbindd.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ config.services.samba.package ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
        script = ''
          set -euo pipefail
          if net ads testjoin >/dev/null 2>&1; then
            echo "Already joined to the AD domain, skipping."
            exit 0
          fi
          joinPassword="$(cat ${config.sops.secrets."nas.ad.password".path})"
          net ads join -U "${cfg.ad.joinAccount}%$joinPassword"
        '';
      };
      systemd.services.samba-smbd = lib.mkIf (!isDc) { after = [ "nas-ad-join.service" ]; requires = [ "nas-ad-join.service" ]; };
      systemd.services.samba-nmbd = lib.mkIf (!isDc) { after = [ "nas-ad-join.service" ]; requires = [ "nas-ad-join.service" ]; };
      systemd.services.samba-winbindd = lib.mkIf (!isDc) { after = [ "nas-ad-join.service" ]; requires = [ "nas-ad-join.service" ]; };

      # Registers the "nfs/<fqdn>" Kerberos principal + keytab entry needed
      # for sec=krb5* NFS exports (see anyNfsKrb5 above).
      systemd.services.nas-nfs-keytab = lib.mkIf anyNfsKrb5 {
        description = "Provision the nfs/${fqdn} Kerberos principal and keytab entry";
        after = [ "network-online.target" ] ++ (if isDc then [ "samba-ad-dc.service" ] else [ "nas-ad-join.service" ]);
        wants = [ "network-online.target" ];
        before = [ "rpc-gssd.service" "rpc-svcgssd.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ config.services.samba.package ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
        script =
          if isDc then ''
            set -euo pipefail
            netbiosHost="$(hostname -s | tr '[:lower:]' '[:upper:]')"
            samba-tool spn add "nfs/${fqdn}" "$netbiosHost$" || true
            samba-tool domain exportkeytab /etc/krb5.keytab --principal="nfs/${fqdn}@${cfg.ad.realm}"
          '' else ''
            set -euo pipefail
            net ads keytab add nfs || true
          '';
      };

      sops.secrets."nas.ad.password" = {
        sopsFile = config.bcl.role.secretFile;
      };

      networking.firewall.allowedTCPPorts =
        [ 139 445 ] # SMB
        ++ [ 111 2049 4000 4001 4002 ] # NFS (rpcbind, nfsd, statd, lockd, mountd)
        ++ [ 88 464 ] # Kerberos, kpasswd
        ++ lib.optionals isDc [ 53 135 389 636 3268 3269 ]; # DNS, RPC epmap, LDAP(S), global catalog
      networking.firewall.allowedUDPPorts =
        [ 111 2049 4001 4002 ] # NFS
        ++ [ 88 464 ] # Kerberos, kpasswd
        ++ lib.optionals isDc [ 53 137 138 ] # DNS, NetBIOS
        ++ lib.optionals (!isDc) [ 137 138 ];
    })
  ];
}
