# Palette colours and dark mode for every GTK app, through the interfaces
# GTK and libadwaita document for it, so a toolkit update leaves it working.
#
# libadwaita (GTK 4) draws every widget itself and ignores the GTK theme
# setting, which is deliberate. What it does support is a list of named
# colours that user CSS can override. They are the CSS variables of the
# 1.6 API and, for older code, the @define-color names with underscores.
# GTK 3 apps get the adw-gtk3 theme, which reads the same @define-color
# names. Each role is listed once below and written in both syntaxes.
#
# The full TTY restyle in gtk-tty.nix targets widget selectors, which
# change between releases, so it only applies to the apps wrapped with it.
# The colours and the dark scheme here reach everything else. Apps wrapped
# with gtk-tty.nix set GTK_THEME, which replaces the theme from
# settings.ini. The colour files still load for them, but their CSS uses
# literal colours, so the names only reach what it leaves to GTK's own
# dark theme, such as the accent.
{
  lib,
  pkgs,
  palette,
  ...
}:
let
  roles = {
    window_bg_color = palette.surface;
    window_fg_color = palette.text;
    view_bg_color = palette.surface;
    view_fg_color = palette.text;
    headerbar_bg_color = palette.surfaceContainer;
    headerbar_fg_color = palette.text;
    headerbar_border_color = palette.outlineVariant;
    card_bg_color = palette.surfaceContainer;
    card_fg_color = palette.text;
    dialog_bg_color = palette.surfaceContainer;
    dialog_fg_color = palette.text;
    popover_bg_color = palette.surfaceContainerHigh;
    popover_fg_color = palette.text;
    sidebar_bg_color = palette.surfaceContainer;
    sidebar_fg_color = palette.text;
    # The accent is the light blue of the Nix logo on the bar. Its
    # foreground is the dark surface, which reads on it.
    accent_bg_color = palette.nix;
    accent_fg_color = palette.surface;
    accent_color = palette.nix;
    destructive_bg_color = palette.alert;
    destructive_fg_color = palette.text;
    destructive_color = palette.alert;
    success_bg_color = palette.gpu;
    success_fg_color = palette.surface;
    success_color = palette.gpu;
    warning_bg_color = palette.disk;
    warning_fg_color = palette.surface;
    warning_color = palette.disk;
    error_bg_color = palette.alert;
    error_fg_color = palette.text;
    error_color = palette.alert;
  };
  named = lib.concatStringsSep "\n" (lib.mapAttrsToList (n: c: "@define-color ${n} ${c};") roles);
  variables = ''
    :root {
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (n: c: "  --${builtins.replaceStrings [ "_" ] [ "-" ] n}: ${c};") roles
    )}
    }
  '';
in
{
  gtk = {
    enable = true;
    colorScheme = "dark";
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    # Without this the theme above would also be imported into GTK 4 apps,
    # where libadwaita restyles everything anyway.
    gtk4.theme = null;
    font = {
      name = "VGA";
      size = 11;
    };
    gtk3.extraCss = named;
    gtk4.extraCss = named + "\n" + variables;
  };
}
