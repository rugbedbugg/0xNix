{
  config,
  lib,
  palette,
  ...
}:
{
  config = lib.mkIf config.programs.lf.enable {
    programs.lf.settings = {
      drawbox = true;
      borderstyle = "box";
      icons = false;
      borderfmt = "\\033[97m";
      promptfmt = "\\033[1;97m%d\\033[0m\\033[1m%f\\033[0m";
      errorfmt = "\\033[1;31m";
      cursoractivefmt = "\\033[7m";
      cursorparentfmt = "\\033[7;90m";
      cursorpreviewfmt = "\\033[4m";
      selectfmt = "\\033[7;97m";
      copyfmt = "\\033[7;33m";
      cutfmt = "\\033[7;35m";
      visualfmt = "\\033[7;36m";
      tagfmt = "\\033[33m";
      menufmt = "\\033[0m";
      menuheaderfmt = "\\033[1m";
      menuselectfmt = "\\033[7m";
    };
    # Override LS_COLORS with the palette's exact RGB values.
    xdg.configFile."lf/colors".text = ''
      fi 38;2;${palette.rgb.textMuted}
      di 38;2;${palette.rgb.border}
      tw 38;2;${palette.rgb.border}
      ow 38;2;${palette.rgb.border}
      st 38;2;${palette.rgb.border}
      ln 38;2;${palette.rgb.cpu}
      or 38;2;${palette.rgb.alert}
      ex 38;2;${palette.rgb.gpu}
      su 38;2;${palette.rgb.gpu}
      sg 38;2;${palette.rgb.gpu}
      pi 38;2;${palette.rgb.disk}
      bd 38;2;${palette.rgb.disk}
      cd 38;2;${palette.rgb.disk}
      so 38;2;${palette.rgb.memory}
    '';
  };
}
