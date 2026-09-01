{ lib, ... }:
let
  inherit (lib) mod;

  pow2 = n: if n <= 0 then 1 else 2 * pow2 (n - 1);

  splitCidr = cidr: let
    parts = lib.strings.splitString "/" cidr;
  in {
    address = builtins.elemAt parts 0;
    prefixLength = lib.strings.toInt (builtins.elemAt parts 1);
  };

  octetsOf = ip: map lib.strings.toInt (lib.strings.splitString "." ip);

  ipToInt = octets: builtins.foldl' (acc: o: acc * 256 + o) 0 octets;

  intToIp = i: lib.concatStringsSep "." (map toString [
    (i / 16777216)
    (mod (i / 65536) 256)
    (mod (i / 256) 256)
    (mod i 256)
  ]);

  networkAddressInt = cidr: let
    parts = splitCidr cidr;
    addrInt = ipToInt (octetsOf parts.address);
    maskInt = 4294967295 - (pow2 (32 - parts.prefixLength) - 1);
  in builtins.bitAnd addrInt maskInt;

  # Extracts the trailing numeric suffix from a hostname (e.g. "srv23" -> 23,
  # "srv" -> 0). Used to derive a per-host number from the `<group><number>`
  # hostname naming convention used across bcl roles (e.g. cluster 2, node 3
  # -> hostname "srv23" -> host number 23).
  hostNumberSuffix = hostName: let
    m = builtins.match "^.*[^0-9]([0-9]+)$" hostName;
  in if m == null then 0 else lib.strings.toInt (builtins.elemAt m 0);
in {
  net = rec {
    # Returns the address part of a CIDR string, e.g. "192.168.41.0" for "192.168.41.0/22".
    cidrAddress = cidr: (splitCidr cidr).address;

    # Returns the prefix length of a CIDR string, e.g. 22 for "192.168.41.0/22".
    cidrPrefixLength = cidr: (splitCidr cidr).prefixLength;

    # Returns the network (base) address of a CIDR string, e.g. "192.168.40.0" for "192.168.41.0/22".
    cidrNetworkAddress = cidr: intToIp (networkAddressInt cidr);

    # Mimics Terraform's `cidrhost(prefix, hostnum)`: calculates the full host
    # IP address for a given host number within the network described by
    # `cidr`. A negative `hostnum` counts backward from the broadcast address
    # (-1 = broadcast address, -2 = last usable address, etc).
    cidrhost = cidr: hostnum: let
      networkInt = networkAddressInt cidr;
      hostBits = 32 - (cidrPrefixLength cidr);
      maxHosts = pow2 hostBits;
      resultInt = if hostnum < 0
        then networkInt + maxHosts + hostnum
        else networkInt + hostnum;
    in intToIp resultInt;

    inherit hostNumberSuffix;

    # Computes a host's IP address (CIDR notation) within `cidr` from the
    # trailing numeric suffix of `hostName` (e.g. cidr "192.168.1.0/24" +
    # hostName "srv25" -> "192.168.1.25/24").
    cidrHostFromHostname = cidr: hostName:
      "${cidrhost cidr (hostNumberSuffix hostName)}/${toString (cidrPrefixLength cidr)}";
  };
}
