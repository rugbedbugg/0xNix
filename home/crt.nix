# Runs crt.frag over the whole screen and binds Super + Shift + C to turn it
# off and on. The shader explains the look.
{ pkgs, ... }:
let
  shader = "${./crt.frag}";

  # The rolling line moves on every frame, but Hyprland draws a frame only
  # when a window changes, so the line would jump. vfr off draws every frame
  # at the monitor's rate. The curve and the glow draw each pixel from the
  # pixels around it. Redrawing only the changed part of the screen would
  # leave smears next to it, so damage tracking is off too. Both cost GPU
  # time and battery even on a still screen. With the shader off, the toggle
  # puts back Hyprland's defaults: vfr on and damage tracking 2, which
  # redraws only what changed.
  #
  # The Lua config rejects `hyprctl keyword`, so the options are set through
  # `hyprctl eval`. An empty path clears the shader. A config reload turns it
  # back on.
  toggle = pkgs.writeShellScript "crt-toggle" ''
    hyprctl=${pkgs.hyprland}/bin/hyprctl
    if [ "$($hyprctl getoption decoration:screen_shader -j | ${pkgs.jq}/bin/jq -r .str)" = "${shader}" ]; then
      options='decoration = { screen_shader = "" }, debug = { vfr = true, damage_tracking = 2 }'
    else
      options='decoration = { screen_shader = "${shader}" }, debug = { vfr = false, damage_tracking = 0 }'
    fi
    $hyprctl eval "hl.config({ $options })" >/dev/null
  '';
in
{
  wayland.windowManager.hyprland = {
    settings.config = {
      decoration.screen_shader = shader;
      debug = {
        vfr = false;
        damage_tracking = 0;
      };
    };
    extraConfig = ''
      hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("${toggle}"), { description = "Toggle CRT screen" })
    '';
  };
}
