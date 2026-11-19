{
  config,
  lib,
  osConfig,
  palette,
  ...
}:
{
  programs.fastfetch.settings = lib.mkIf config.programs.fastfetch.enable (
    let
      keyWidth = 8;
      valueWidth = 28;
      inner = keyWidth + valueWidth + 2;
      title = "${config.home.username}@${osConfig.networking.hostName}";
      colour = role: "{#38;2;${palette.rgb.${role}}}";
      edge = colour "border";
      repeat = n: s: lib.concatStrings (lib.genList (_: s) n);
      padRight = n: s: s + repeat (n - lib.stringLength s) " ";
      row = type: key: role: format: {
        inherit type;
        key = "${edge}│ ${colour role}${padRight keyWidth key}{#}";
        format = "${format} ${edge}│";
      };
      padded = field: "{${field}<${toString valueWidth}}";
    in
    {
      logo.type = "none";
      display = {
        separator = "";
        # VGA has no bold weight.
        brightColor = false;
        color = {
          keys = "38;2;${palette.rgb.border}";
          output = "38;2;${palette.rgb.text}";
        };
        percent.color = {
          green = "38;2;${palette.rgb.gpu}";
          yellow = "38;2;${palette.rgb.disk}";
          red = "38;2;${palette.rgb.alert}";
        };
      };
      modules = [
        {
          type = "custom";
          format = "${edge}╭─ ${colour "text"}${title}${edge} ${
            repeat (inner - 3 - lib.stringLength title) "─"
          }╮";
        }
        (row "os" "distro" "nix" (padded "pretty-name"))
        (row "kernel" "kernel" "cpu" (padded "release"))
        (row "uptime" "uptime" "disk" (padded "formatted"))
        (row "shell" "shell" "gpu" "{pretty-name<9}{version<19}")
        (row "wm" "wm" "swap" "{pretty-name<9}{version<19}")
        (row "memory" "mem" "memory" "{used>8} / {total>8} ({percentage>4})  ")
        (row "packages" "pkgs" "nix" (padded "all"))
        {
          type = "custom";
          format = "${edge}╰${repeat inner "─"}╯";
        }
      ];
    }
  );
  programs.btop.settings = lib.mkIf config.programs.btop.enable {
    theme_background = false;
  };
}
