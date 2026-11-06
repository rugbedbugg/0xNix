{ vars, ... }:
{
  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/hardware/amd-laptop.nix
  ];

  networking.hostName = vars.hostname;
}
