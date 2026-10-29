{ pkgs-unstable, ... }:
{
  # Configured TUI apps (MPD + rmpc, btop, youtube-tui). Plain package
  # installs live in packages.nix.

  # rmpc is an MPD client, not a standalone player — it needs an actual MPD
  # server to talk to. "pipewire" is a real, confirmed MPD output plugin on
  # this package build (checked `mpd --version`'s Output plugins list), the
  # correct native choice on this pipewire-based system.
  services.mpd = {
    enable = true;
    extraConfig = ''
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

  # Fastfetch runs on its own native defaults — no custom config. Custom
  # layouts tend to lean on Nerd Font icon glyphs and shell-outs (uptime -p,
  # free | awk) that don't hold up against this rice's plain bitmap VGA
  # font; fastfetch's own built-in modules (native Uptime/Memory/Swap, no
  # icons) sidestep both problems.

  programs.btop = {
    enable = true;
    package = pkgs-unstable.btop;
    settings = {
      # Let the terminal's own background show through instead of btop
      # painting its own, same as vim's oxide colour scheme.
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
