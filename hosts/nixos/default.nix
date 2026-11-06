{ vars, ... }:
{
  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/hardware/amd-laptop.nix
  ];

  networking.hostName = vars.hostname;

  # The Arch install on the other partition is its own node, so each OS
  # names itself instead of both claiming the oxide1-6 hostname.
  services.tailscale.extraSetFlags = [ "--hostname=oxide1-6-nixos" ];
}
