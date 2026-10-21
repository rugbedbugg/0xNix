{
  # Same as the Arch install: Tailscale's defaults (MagicDNS on, no exit
  # node, no routes, no Tailscale SSH) and port 41641 left closed, so peers
  # connect through NAT traversal.
  services.tailscale.enable = true;

  # KDE Connect, reachable only from the paired phone (Redmi 13 5G) over
  # Tailscale, like the ufw rule on Arch. programs.kdeconnect would open
  # ports 1714-1764 on every interface instead.
  networking.firewall.extraCommands = ''
    for proto in tcp udp; do
      iptables -A nixos-fw -i tailscale0 -s 100.67.86.76 -p $proto --dport 1714:1764 -j nixos-fw-accept
    done
  '';
}
