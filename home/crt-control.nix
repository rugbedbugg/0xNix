# The commands that turn the CRT screen shader on and off. The toggle
# (crt.nix) and the screenshot (keybinds.nix) both use them.
#
# The rolling line moves on every frame, but Hyprland draws a frame only
# when a window changes, so the line would jump. vfr off draws every frame
# at the monitor's rate. The curve and the glow draw each pixel from the
# pixels around it. Redrawing only the changed part of the screen would
# leave smears next to it, so damage tracking is off too. Both cost GPU
# time and battery even on a still screen. With the shader off, the options
# go back to Hyprland's defaults: vfr on and damage tracking 2, which
# redraws only what changed.
#
# The Lua config rejects `hyprctl keyword`, so the options are set through
# `hyprctl eval`. An empty path clears the shader. A config reload turns it
# back on.
{ pkgs }:
let
  shader = "${./crt.frag}";
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
in
{
  inherit shader;

  # Exits 0 while the shader is on.
  isOn = pkgs.writeShellScript "crt-is-on" ''
    [ "$(${hyprctl} getoption decoration:screen_shader -j | ${pkgs.jq}/bin/jq -r .str)" = "${shader}" ]
  '';

  on = pkgs.writeShellScript "crt-on" ''
    options='decoration = { screen_shader = "${shader}" }, debug = { vfr = false, damage_tracking = 0 }'
    ${hyprctl} eval "hl.config({ $options })" >/dev/null
  '';

  off = pkgs.writeShellScript "crt-off" ''
    options='decoration = { screen_shader = "" }, debug = { vfr = true, damage_tracking = 2 }'
    ${hyprctl} eval "hl.config({ $options })" >/dev/null
  '';
}
