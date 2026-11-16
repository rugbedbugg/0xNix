{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # Start the application daemon with the graphical session.
  systemd.user.services.wayland-wm-app-daemon.wantedBy = [ "graphical-session.target" ];
}
