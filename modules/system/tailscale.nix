{ lib, vars, ... }:
let
  # Null leaves the KDE Connect ports closed on every interface.
  phone = vars.phoneAddress or null;
in
{
  # Same as the Arch install: Tailscale's defaults (MagicDNS on, no exit
  # node, no routes, no Tailscale SSH) and port 41641 left closed, so peers
  # connect through NAT traversal.
  services.tailscale.enable = true;

  # The Arch install on the other partition is its own node, so each OS
  # names itself instead of both claiming the same hostname. A host can
  # override the name.
  services.tailscale.extraSetFlags = lib.mkDefault [
    "--hostname=${lib.toLower vars.hostname}-nixos"
  ];

  # KDE Connect, reachable only from the paired phone (Redmi 13 5G) over
  # Tailscale, like the ufw rule on Arch. programs.kdeconnect would open
  # ports 1714-1764 on every interface instead.
  networking.firewall.extraCommands = lib.optionalString (phone != null) ''
    for proto in tcp udp; do
      iptables -A nixos-fw -i tailscale0 -s ${phone} -p $proto --dport 1714:1764 -j nixos-fw-accept
    done
  '';
}
