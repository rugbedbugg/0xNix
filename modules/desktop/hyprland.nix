{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  services.displayManager = {
    defaultSession = "hyprland-uwsm";
    sddm.enable = false;
    ly = {
      enable = true;
      # Wayland-only rice; ly never needs to offer a plain X session.
      x11Support = false;
      settings = {
        # ly's own compiled defaults are already white-on-default/bold-red-error;
        # declared explicitly so the palette is documented, not inherited.
        bg = "0x00000000";
        fg = "0x00FFFFFF";
        border_fg = "0x00FFFFFF";
        error_bg = "0x00000000";
        error_fg = "0x01FF0000";
        # The one deliberate exception to this rice's no-animation rule.
        # ly-lock (github:rugbedbugg/ly-lock) reads these settings and shows
        # the same screen when the session is locked.
        animation = "matrix";
        hide_borders = false;
        blank_box = true;
        # Matches waybar's clock format.
        clock = "%a %d %b  %H:%M";
      };
    };
  };

  security.polkit.enable = true;
  # Installs ly-lock and its PAM service.
  programs.ly-lock.enable = true;
}
