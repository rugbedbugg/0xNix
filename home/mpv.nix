# mpv in the rice's colours (mpv-theme.nix). The package comes from
# apps.nix. Only the two config files live here.
{ palette, ... }:
let
  theme = import ./mpv-theme.nix { inherit palette; };
in
{
  xdg.configFile = {
    "mpv/mpv.conf".text = theme.config;
    "mpv/script-opts/osc.conf".text = theme.osc;
  };
}
