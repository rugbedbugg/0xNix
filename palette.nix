# The rice's fixed colour palette. Every module reads its colours from here,
# so the hex values live in one place. Roles are named for what they mean on
# waybar.
#
# The hues are One Dark's, as the onedark.vim port of Atom's theme defines
# them. The base is the rice's own. The greys are neutral, built around
# #242424, foot's old default background. Text is #eceff4, brighter than
# One Dark's. Border and black keep the rice's white rule and its mask.
# Swap and the diff fills are blends of One Dark hues over the surface
# colour.
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
    surface = "#242424";
    # Slightly lighter fills, for blends and raised editor surfaces.
    surfaceContainer = "#2a2a2a";
    surfaceContainerHigh = "#343434";
    surfaceContainerHighest = "#3c3c3c";

    # Text, and the fill of a selected item in reverse video.
    text = "#eceff4";
    # Dimmer text, such as comments and inactive status lines.
    textDim = "#6b6b6b";
    # A step below the text colour. The VGA font has no bold weight, so file
    # names in lf use it to read as quieter than directories.
    textMuted = "#8a8a8a";
    # Disabled items, such as Mic OFF and Cam OFF.
    outline = "#6b6b6b";
    # Inactive borders, as in Hyprland.
    outlineVariant = "#444444";
    # The white of every border in the rice.
    border = "#ffffff";

    # Waybar's stat hues.
    cpu = "#56b6c2";
    memory = "#c678dd";
    # A dimmer shade of the RAM purple: 75% of it over the surface colour.
    swap = "#9e63af";
    disk = "#e5c07b";
    gpu = "#98c379";

    # The Nix logo on waybar.
    nix = "#61afef";
    # The empty slot behind a wallpaper preview.
    black = "#000000";

    # Reserved for states that need action: errors, deletions, live mic. The
    # location marker on the clock's world map is the one other use.
    alert = "#e06c75";

    # Diff backgrounds: each hue blended over the surface colour. Green and
    # red take 25%, the changed line's yellow 20% and the changed text 30%.
    # Text stays readable on all four, at 6.5:1 or better.
    diffAdd = "#414c39";
    diffChange = "#4b4335";
    diffDelete = "#533638";
    diffText = "#5e533e";
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
  # Blue has no stat hue, so it takes the Nix logo's. Magenta takes the RAM
  # purple in both rows. The six hues are the same in both rows, as in One
  # Dark's terminal theme. Black is a raised surface, since the plain
  # surface colour is the background. Bright black is the dim text grey
  # that fish uses for autosuggestions. White is the text colour in both
  # rows.
  ansi = {
    regular = map (role: colours.${role}) [
      "surfaceContainer"
      "alert"
      "gpu"
      "disk"
      "nix"
      "memory"
      "cpu"
      "text"
    ];
    bright = map (role: colours.${role}) [
      "textDim"
      "alert"
      "gpu"
      "disk"
      "nix"
      "memory"
      "cpu"
      "text"
    ];
  };
in
colours
// {
  bare = builtins.mapAttrs (_: builtins.substring 1 6) colours;
  rgb = builtins.mapAttrs (_: rgb) colours;
  inherit ansi;
}
