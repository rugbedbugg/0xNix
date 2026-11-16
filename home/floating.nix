# Loads floating.lua, which opens the windows of the Super + Alt launches
# (keybinds.nix) as golden rectangles. This module fills in the script's
# numbers. The script holds the logic and explains it.
{ config, lib, ... }:
let
  geometry = import ./overlay-geometry.nix { inherit (config.desktop) screen; };
  # The work area the windows are centred in. The values are whole pixels, for
  # the same reason as in overlay-geometry.nix: centring an odd size would
  # land on a half pixel. The bars' exclusive zones push the area down and pull
  # it up.
  area = {
    x = 0;
    y = geometry.bar;
    width = config.desktop.screen.width;
    height = config.desktop.screen.height - geometry.bar - geometry.bottomBar;
  };
  values = {
    # A window is this share of the work area wide. Its height is this share
    # of its own width, the golden ratio's inverse.
    "@share@" = "0.45";
    "@ratio@" = "0.618";
    # Pixels between the stacked positions of windows on one workspace.
    "@step@" = "32";
    # How far Super + Shift + arrow moves a floating window, in pixels.
    "@moveStep@" = "40";
    # How long a Super + Alt launch waits for its window, in milliseconds.
    # LibreOffice takes several seconds to start cold.
    "@armMs@" = "10000";
    "@areaX@" = toString area.x;
    "@areaY@" = toString area.y;
    "@areaW@" = toString area.width;
    "@areaH@" = toString area.height;
  };
  script = builtins.replaceStrings (builtins.attrNames values) (builtins.attrValues values) (
    builtins.readFile ./floating.lua
  );
in
{
  wayland.windowManager.hyprland.extraConfig = lib.mkAfter script;
}
