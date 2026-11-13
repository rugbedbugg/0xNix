# The mpv theme: its main config and the on-screen controller's config, both
# built from the palette. mpv.nix puts them in ~/.config/mpv. keybinds.nix
# gives the YouTube player the same two files, since that one runs with its
# own config directory.
#
# libass draws the OSD and the subtitles, and it needs an outline font. The
# VGA font is a bitmap, so these use Big Blue Terminal, the outline font that
# zapfast.nix and gtk.nix use for the same reason. Square corners, flat fills
# and a plain 1px edge match the bar and the tooltips. The controller is
# opaque, like the bar. mpv.conf reads a # as a comment, so the colours there
# are quoted.
{ palette }:
{
  config = ''
    osd-font=BigBlueTermPlus Nerd Font
    osd-font-size=30
    osd-bold=no
    osd-color="${palette.text}"
    osd-border-color="${palette.surface}"
    osd-border-size=2
    osd-shadow-offset=0
    osd-bar-align-y=0.9
    sub-font=BigBlueTermPlus Nerd Font
    sub-font-size=40
    sub-bold=no
    sub-color="${palette.text}"
    sub-border-color="${palette.surface}"
    sub-border-size=2.5
    sub-shadow-offset=0
    background=color
    background-color="${palette.surface}"
    border=no
  '';

  osc = ''
    layout=bottombar
    seekbarstyle=bar
    seekrangestyle=line
    icon_style=classic
    boxalpha=0
    background_color=${palette.surface}
    timecode_color=${palette.text}
    title_color=${palette.text}
    time_pos_color=${palette.text}
    time_pos_outline_color=${palette.surface}
    buttons_color=${palette.text}
    top_buttons_color=${palette.text}
    held_element_color=${palette.outline}
  '';
}
