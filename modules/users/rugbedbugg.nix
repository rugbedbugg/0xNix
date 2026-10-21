{ pkgs, vars, ... }:
{
  users.users.${vars.username} = {
    isNormalUser = true;
    description = vars.displayName;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.fish;
  };
}
