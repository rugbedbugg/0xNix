# Zathura in the rice's TTY look. It draws its own page area, status bar and
# input bar from these options, so no GTK theme is needed. Every colour comes
# from palette.nix. Zathura has no borders or rounded corners to restyle, so
# only fill, text and the VGA font carry over. Selected items are in reverse
# video, as in the rest of the rice.
#
# Zathura opens files from its own input bar (:open) and never shows a file
# dialog, so nothing here needs the portal.
{
  config,
  lib,
  palette,
  ...
}:
let
  # Search matches are drawn over the page, so they need an alpha. Zathura
  # parses the colour with GDK, which accepts rgba().
  translucent =
    role: alpha: "rgba(${builtins.replaceStrings [ ";" ] [ "," ] palette.rgb.${role}},${alpha})";
in
{
  config = lib.mkIf config.programs.zathura.enable {
    programs.zathura = {
      options = {
        font = "VGA 11";

        default-bg = palette.surface;
        default-fg = palette.text;

        statusbar-bg = palette.surfaceContainerHigh;
        statusbar-fg = palette.text;
        inputbar-bg = palette.surface;
        inputbar-fg = palette.text;

        notification-bg = palette.surface;
        notification-fg = palette.text;
        # Red only where something went wrong, same rule as the rest of the
        # rice.
        notification-error-bg = palette.surface;
        notification-error-fg = palette.alert;
        notification-warning-bg = palette.surface;
        notification-warning-fg = palette.disk;

        completion-bg = palette.surface;
        completion-fg = palette.text;
        completion-group-bg = palette.surface;
        completion-group-fg = palette.textMuted;
        completion-highlight-bg = palette.text;
        completion-highlight-fg = palette.surface;

        index-bg = palette.surface;
        index-fg = palette.text;
        index-active-bg = palette.text;
        index-active-fg = palette.surface;

        highlight-color = translucent "disk" "0.5";
        highlight-active-color = translucent "nix" "0.5";
        highlight-fg = palette.surface;

        # Ctrl-R recolours the pages with the rice's surface and text colours.
        # It stays off by default, since it also inverts images.
        recolor = false;
        recolor-lightcolor = palette.surface;
        recolor-darkcolor = palette.text;
        recolor-keephue = false;

        statusbar-home-tilde = true;
        window-title-home-tilde = true;
      };
    };
  };
}
