{ pkgs, ... }:
{
  # The NixOS Hyprland module supplies its matching Hyprland and GTK backends.
  xdg.portal = {
    enable = true;
    # File dialogs open lf in a terminal instead of a GTK window. The lf
    # Keep the wrapper beside the file manager configuration.
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
