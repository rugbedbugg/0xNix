{
  lib,
  palette,
  ...
}:
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # The daemon behind uwsm-app, which every keybind launches through. It
  # would otherwise start on the first launch and make that one take ~1s.
  systemd.user.services.wayland-wm-app-daemon.wantedBy = [ "graphical-session.target" ];



}
