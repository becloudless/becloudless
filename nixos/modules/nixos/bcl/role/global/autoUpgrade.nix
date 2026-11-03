{ config, lib, pkgs, ... }:

let
  cfg = config.bcl.role.autoUpgrade;

  # Weekly, on a weekday and a time (01:00 to 05:59) that are fixed for a host: derived from a hash of the hostname, so the hosts do not
  # all hit the git server and the cache at the same moment. No random delay, see the comment at `dates` below.
  hostHash = lib.fromHexString (builtins.substring 0 8 (builtins.hashString "sha256" config.networking.hostName));
  weekdays = [ "Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun" ];
  pad2 = n: lib.fixedWidthNumber 2 n;

  # `srv3` -> 3, `backup-hot1` -> 1, `salon-0` -> 0, `foo` -> null
  hostNumberMatch = builtins.match ".*[^0-9]([0-9]+)" config.networking.hostName;
  hostNumber = if hostNumberMatch == null then null else lib.toInt (builtins.head hostNumberMatch);

  weekday =
    if cfg.useHostNumber && hostNumber != null
    then lib.mod (hostNumber + 6) 7 # 1 -> Mon, 2 -> Tue, ..., 7 -> Sun, 8 -> Mon
    else lib.mod hostHash 7;
  upgradeSchedule = "${builtins.elemAt weekdays weekday} *-*-* ${pad2 (1 + lib.mod (hostHash / 7) 5)}:${pad2 (lib.mod (hostHash / 35) 60)}:00";
in
{
  options.bcl.role.autoUpgrade.useHostNumber = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Pick the weekday of the upgrade from the number at the end of the hostname (`srv1` is on Monday, `srv2` on Tuesday, ... `srv7` on
      Sunday, `srv8` on Monday again) instead of from a hash of the hostname. The hashes of a few hosts often fall on the same day, the
      numbers of the nodes of a cluster never do. Hosts without a number in their name use the hash. The time of the day is always
      from the hash.
    '';
  };


  config = lib.mkIf (config.bcl.role.name != "") {

    environment.systemPackages = with pkgs; [
      git
      nmap # ssh over tls
    ];

    home-manager.users.root = { lib, pkgs, ... }: {
      home.file.".ssh/config".text = ''
        Host gitea.${config.bcl.global.domain}
          IdentityFile /nix/etc/ssh/ssh_host_ed25519_key
      '';

      home.stateVersion = "23.11";
    };

    system.autoUpgrade = {
      enable = true;
      operation = "boot";
      flake = "'git+ssh://git@gitea.${config.bcl.global.domain}/${config.bcl.global.name}/infra?ref=main&dir=nixos#${config.networking.hostName}'";
      flags = [ "--refresh" "--no-write-lock-file" ];
      # No `randomizedDelaySec`: with a random delay (even a fixed one) systemd computes the next run from the current time instead of
      # the last trigger, so a machine that is only up for a few hours at a time never reaches it and the `Persistent` catch-up never fires.
      # Verified on systemd 260: weekly + Persistent + backdated stamp runs at timer start, the same with RandomizedDelaySec=72h does not.
      # The spread is done with the fixed weekday and time of each host instead (`upgradeSchedule`), same catch-up behaviour.
      dates = upgradeSchedule;
    };

    systemd.timers.nixos-upgrade.timerConfig.Persistent = lib.mkForce true; # so the timer fires even if the system was off at the scheduled time

  };
}
