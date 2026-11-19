{ lib, ... }:
{
  programs.fish = {
    enable = true;
    interactiveShellInit = lib.mkBefore ''
      set -g fish_greeting
    '';
    functions.starship_transient_prompt_func = "starship module character $argv";
  };
  # A transient prompt keeps completed commands short when foot reflows.
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableTransience = true;
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };
}
