{
  pkgs-unstable,
  aws-agent-toolkit,
  vars,
  palette,
  ...
}:
{
  imports = [
    ../modules/system
    ../modules/desktop
    ../modules/development
    ../modules/users/rugbedbugg.nix
  ];

  system.stateVersion = "26.05";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "before-home-manager";
    extraSpecialArgs = { inherit pkgs-unstable aws-agent-toolkit vars palette; };
    users.${vars.username} = import ../home/rugbedbugg;
  };
}
