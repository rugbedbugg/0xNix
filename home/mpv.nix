# Apply the palette to mpv's player and on-screen controls.
{
  config,
  lib,
  palette,
  ...
}:
let
  theme = import ./mpv-theme.nix { inherit palette; };
in
{
  xdg.configFile = lib.mkIf config.programs.mpv.enable {
    "mpv/mpv.conf".text = theme.config;
    "mpv/script-opts/osc.conf".text = theme.osc;
  };
}
