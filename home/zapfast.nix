# A ZapFast theme in the rice's TTY look. ZapFast is an egui app, so GTK and
# Qt themes don't reach it. It reads colour files from its themes folder
# instead. The file's name is the theme's name in Settings. Pick "0xNix"
# under Settings, Appearance. The choice is stored in settings.json. That
# file also holds the app lock, so Home Manager leaves it alone.
#
# Every colour comes from palette.nix. The window and the chat list take the
# surface colour. Cards, fields and menus step up through the container
# shades. The selected chat is a grey step, not reverse video. Only the
# accent is in reverse video: it is the text colour, and the text on it is
# the surface colour. Borders and dividers take the muted outline grey, as
# the rice's own dividers do. Red marks errors only.
#
# A theme cannot change the corner radius. ZapFast fixes its radii in code.
#
# The System font in Settings is fontconfig's answer for system-ui, which is
# DejaVu Sans here. ZapFast draws text from outlines and cannot draw the VGA
# bitmap font. Shared font styling points system-ui at Big Blue Terminal.
# The Plus variant covers more Unicode than the strict CP437 one. Restart
# ZapFast and pick System under Settings, Appearance, Font.
{
  config,
  lib,
  palette,
  ...
}:
{
  config = lib.mkIf config.desktop.applicationThemes.zapfast.enable {
    xdg.configFile."zapfast/themes/0xNix.json".text = builtins.toJSON {
      base = "dark";
      colors = {
        window = palette.surface;
        panel = palette.surface;
        surface = palette.surfaceContainer;
        surface_hover = palette.surfaceContainerHigh;
        surface_active = palette.surfaceContainerHighest;
        overlay = palette.surfaceContainer;

        text = palette.text;
        secondary = palette.textMuted;
        dim = palette.outline;

        accent = palette.text;
        accent_hover = palette.border;
        on_accent = palette.surface;

        danger = palette.alert;
        warning = palette.disk;

        outline = palette.outline;
        shadow = palette.black;

        chat = palette.surface;
        bubble_in = palette.surfaceContainer;
        bubble_out = palette.surfaceContainerHighest;
        link = palette.nix;
        read = palette.cpu;
      };
    };
  };
}
