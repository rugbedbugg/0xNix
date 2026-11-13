{ config, 
  lib,
  osConfig,
  pkgs-unstable,
  palette,
  ...
}:
{
  # Configured TUI apps (MPD + rmpc, btop, youtube-tui). Plain package
  # installs live in packages.nix.

  # rmpc is an MPD client, not a standalone player — it needs an actual MPD
  # server to talk to. "pipewire" is a real, confirmed MPD output plugin on
  # this package build (checked `mpd --version`'s Output plugins list), the
  # correct native choice on this pipewire-based system.
  #
  # auto_update makes mpd watch the music directory through inotify. Songs
  # added, changed or removed there show up in rmpc without an update.
  services.mpd = {
    enable = true;
    extraConfig = ''
      auto_update "yes"

      audio_output {
        type "pipewire"
        name "PipeWire Output"
      }
    '';
  };

  programs.rmpc = {
    enable = true;
    package = pkgs-unstable.rmpc;
    config = ''
      (
          address: "127.0.0.1:6600",
          password: None,
          theme: None,
          enable_mouse: true,
          volume_step: 5,
          wrap_navigation: true,
      )
    '';
  };

  # Fastfetch prints a boxed card of system facts. Only fastfetch's own
  # modules fill it, so nothing shells out to uptime or free. Every glyph is
  # one the VGA font has, so the card uses no Nerd Font icons. Each key takes
  # a palette hue. The values are padded to one width, so the right edge of
  # the box lines up.
  programs.fastfetch =
    let
      keyWidth = 8;
      valueWidth = 28;
      # One space, the key, the value and one space between the edges.
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
      enable = true;
      package = pkgs-unstable.fastfetch;
      settings = {
        logo.type = "none";
        display = {
          separator = "";
          # Fastfetch would print keys in bold. VGA has no bold weight.
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
          # The name takes a fixed column so the versions line up.
          (row "shell" "shell" "gpu" "{pretty-name<9}{version<19}")
          (row "wm" "wm" "swap" "{pretty-name<9}{version<19}")
          # 8 + 3 + 8 + 1 + 6 characters, then two spaces fill the column.
          (row "memory" "mem" "memory" "{used>8} / {total>8} ({percentage>4})  ")
          (row "packages" "pkgs" "nix" (padded "all"))
          {
            type = "custom";
            format = "${edge}╰${repeat inner "─"}╯";
          }
        ];
      };
    };

  programs.btop = {
    enable = true;
    package = pkgs-unstable.btop;
    settings = {
      # Let the terminal's own background show through instead of btop
      # painting its own, same as vim's 0xNix colour scheme.
      theme_background = false;
    };
  };

  # youtube-tui rewrites main.yml every time it starts, so a hand edit gets
  # lost. Every key has a built-in default. Only env is set here, and it
  # replaces the default env as a whole, so every entry is listed. foot
  # stands in for konsole, which isn't installed. youtube-tui can't write to
  # this read-only file and starts anyway. force replaces the file it wrote
  # before this existed. The package itself is in the flake's apps profile.
  xdg.configFile."youtube-tui/main.yml" = {
    force = true;
    text = ''
      env:
        save-path: ~/.local/share/youtube-tui/saved/
        terminal-emulator: foot
        browser: xdg-open
        download-path: ~/Downloads/%(title)s-%(id)s.%(ext)s
        video-player: mpv
        youtube-downloader: yt-dlp
    '';
  };
}
