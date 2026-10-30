{ pkgs, ... }:
{
  # The NixOS Hyprland module supplies its matching Hyprland and GTK backends.
  xdg.portal = {
    enable = true;
    # File dialogs open lf in a terminal instead of a GTK window. The lf
    # wrapper and its config live in home/rugbedbugg/files.nix.
    extraPortals = [ pkgs.xdg-desktop-portal-termfilechooser ];
    config.hyprland = {
      default = [
        "hyprland"
        "gtk"
      ];
      "org.freedesktop.impl.portal.FileChooser" = [ "termfilechooser" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
    };
  };
}
