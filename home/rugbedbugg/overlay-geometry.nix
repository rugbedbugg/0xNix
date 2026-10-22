# Pixel geometry shared by the floating special-workspace windows
# (keybinds.nix) and the label bar on their top-left corner
# (desktop-tools.nix). Both read it from here so the bar stays flush with
# the window frame at any resolution. The numbers in the comments are for
# a 1920x1080 screen.
{ screen }:
let
  # Height of the main waybar. Its exclusive zone pushes the work area down.
  bar = 32;
  # Hyprland draws the window border outside the window box.
  border = 2;
  labelHeight = 28;
  labelWidth = 400;

  # 101/120 of the screen width at the screen's own aspect ratio: 1616x909,
  # about 70.8% of the screen area.
  width = screen.width * 101 / 120;
  height = width * screen.height / screen.width;

  # Pin the position instead of letting Hyprland center the window. An odd
  # height centered in the work area would land on a half pixel. Nix
  # integer division rounds down instead: x = 152, y = 32 + 69 = 101.
  x = (screen.width - width) / 2;
  y = bar + (screen.height - bar - height) / 2;
in
{
  inherit
    width
    height
    x
    y
    ;

  # The label bar sits directly above the window frame. Its left edge is
  # flush with the outer border and its own 2px bottom border lands on the
  # window's top border rows. waybar counts margin-top from below the main
  # bar's exclusive zone, so the bar top (y - 28 = 73) becomes 73 - 32 = 41.
  # It sets the width through both side margins: with position=top, an
  # explicit width makes waybar drop the side anchors and center the bar.
  label = {
    height = labelHeight;
    marginTop = y - labelHeight - bar;
    marginLeft = x - border;
    marginRight = screen.width - (x - border) - labelWidth;
  };
}
