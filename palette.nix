# The rice's fixed colour palette. Every module reads its colours from here,
# so the hex values live in one place. Roles are named for what they mean on
# waybar.
#
# Each colour is a 6-digit hex string with a leading #, without alpha. The
# derived forms live apart from the colours, so a loop over the colours
# never meets them:
#   palette.bare.<role>  hex without the #, for consumers that append their
#                        own alpha (fuzzel, Hyprland, ly)
#   palette.rgb.<role>   decimal R;G;B, for escape sequences (lf)
#   palette.ansi         the terminal's 16 colours as two lists of 8, regular
#                        and bright, in ANSI order (foot, Neovim's :terminal)
let
  colours = {
    # Fill of the bar, tooltips, menus and the GTK theme.
    surface = "#20242c";
    # Slightly lighter fills, for blends and raised editor surfaces.
    surfaceContainer = "#262b34";
    surfaceContainerHigh = "#2c313b";
    surfaceContainerHighest = "#343a45";

    # Text, and the fill of a selected item in reverse video.
    text = "#eceff4";
    # Dimmer text, such as comments and inactive status lines.
    textDim = "#8a8f99";
    # A step below the text colour. The VGA font has no bold weight, so file
    # names in lf use it to read as quieter than directories.
    textMuted = "#9aa0aa";
    # Disabled items and line numbers.
    outline = "#6c7380";
    # Inactive borders, as in Hyprland.
    outlineVariant = "#444444";
    # The white of every border in the rice.
    border = "#ffffff";

    # Waybar's stat hues.
    cpu = "#5fd7ff";
    memory = "#c792ea";
    swap = "#9d8fbf";
    disk = "#e5c07b";
    gpu = "#7ee787";

    # The Nix logo on waybar.
    nix = "#7ebae4";
    # The empty slot behind a wallpaper preview.
    black = "#000000";

    # Reserved for states that need action: errors, deletions, live mic.
    alert = "#ff0000";

    # Diff backgrounds: each hue blended over the surface colour.
    diffAdd = "#375442";
    diffChange = "#47433b";
    diffDelete = "#571b21";
    diffText = "#786a4f";
  };

  digit = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "a" = 10;
    "b" = 11;
    "c" = 12;
    "d" = 13;
    "e" = 14;
    "f" = 15;
  };
  byte = hex: i: digit.${builtins.substring i 1 hex} * 16 + digit.${builtins.substring (i + 1) 1 hex};
  rgb =
    hex:
    builtins.concatStringsSep ";" (
      map (i: toString (byte (builtins.substring 1 6 hex) i)) [
        0
        2
        4
      ]
    );
  # Blue has no stat hue, so it takes the Nix logo's. Bright magenta takes
  # the RAM purple and magenta its dimmer swap shade, so the pair stays
  # distinguishable. Black is a raised surface because the plain surface
  # colour is the background, and bright black is the disabled-text grey
  # that fish uses for autosuggestions.
  ansi = {
    regular = map (role: colours.${role}) [
      "surfaceContainerHighest"
      "alert"
      "gpu"
      "disk"
      "nix"
      "swap"
      "cpu"
      "text"
    ];
    bright = map (role: colours.${role}) [
      "outline"
      "alert"
      "gpu"
      "disk"
      "nix"
      "memory"
      "cpu"
      "border"
    ];
  };
in
colours
// {
  bare = builtins.mapAttrs (_: builtins.substring 1 6) colours;
  rgb = builtins.mapAttrs (_: rgb) colours;
  inherit ansi;
}
