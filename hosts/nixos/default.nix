{
  pkgs-unstable,
  vars,
  palette,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/system
    ../../modules/hardware/amd-laptop.nix
    ../../modules/desktop
    ../../modules/development
    ../../modules/users/rugbedbugg.nix
  ];

  networking.hostName = vars.hostname;
  system.stateVersion = "26.05";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "before-home-manager";
    extraSpecialArgs = { inherit pkgs-unstable vars palette; };
    users.${vars.username} = import ../../home/rugbedbugg;
  };
}
