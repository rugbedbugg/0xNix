# Desktop session pieces apart from the bars (waybar.nix and
# waybar-side-bars.nix): the clipboard, screenshot and font packages, the GTK 4
# tty theme file, foot, fuzzel, KDE Connect, mako, the polkit agent, hypridle
# and the charger watcher.
{
  osConfig,
  pkgs,
  palette,
  ...
}:
let
  gtkTty = import ./gtk-tty.nix { inherit pkgs palette; };
  pavucontrol = gtkTty.wrap pkgs.pavucontrol "pavucontrol";
  scripts = import ./status-scripts.nix { inherit pkgs osConfig palette; };
in
{
  home.packages = with pkgs; [
    wl-clipboard
    grim
    slurp
    libnotify
    # Wrapped to run with the tty theme below.
    pavucontrol
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.dejavu-sans-mono
    uni-vga
  ];
  xdg.dataFile."themes/tty/gtk-4.0/gtk.css".source = gtkTty.css;
  programs = {
    foot = {
      enable = true;
      settings.main = {
        font = "VGA:size=11";
        pad = "2x2";
      };
      # The shell's 16 ANSI colours, so starship, fish, git and ls draw in
      # the palette instead of foot's defaults. Alpha stays at foot's default,
      # which keeps the terminal opaque.
      settings.colors-dark =
        let
          slots =
            prefix: colours:
            builtins.listToAttrs (
              builtins.genList (i: {
                name = "${prefix}${toString i}";
                value = builtins.substring 1 6 (builtins.elemAt colours i);
              }) 8
            );
        in
        {
          background = palette.bare.surface;
          foreground = palette.bare.text;
        }
        // slots "regular" palette.ansi.regular
        // slots "bright" palette.ansi.bright;
    };
    fuzzel = {
      enable = true;
      settings = {
        main = {
          font = "VGA:size=11";
          # Same aspect ratio as the screen (1920x1080 = 16:9), at roughly
          # the same screen coverage the original default (width=30,
          # lines=15) had — not fullscreen. Solved empirically against this
          # exact font/size (VGA:size=11 renders a fixed 12x26px cell, plus
          # fuzzel's own default padding/border): width=42, lines=11 ->
          # 588x332px (ratio 1.77, vs. screen's 1.78; area within 1% of the
          # original 444x436px). Padding/anchor left at fuzzel's own
          # defaults (center, hpad=40, vpad=8) — only width/lines changed.
          width = 42;
          lines = 11;
        };
        colors = {
          background = "${palette.bare.surface}ff";
          text = "${palette.bare.border}ff";
          match = "${palette.bare.alert}ff";
          selection = "${palette.bare.border}ff";
          selection-text = "${palette.bare.surface}ff";
          selection-match = "${palette.bare.alert}ff";
          border = "${palette.bare.border}ff";
        };
        border = {
          width = 2;
          radius = 0;
        };
      };
    };
  };

  services = {
    # Runs the daemon and its tray icon. Pair the phone again from it: this
    # machine is a new device to KDE Connect.
    kdeconnect = {
      enable = true;
      indicator = true;
    };
    mako = {
      enable = true;
      settings = {
        border-size = 2;
        border-radius = 0;
        border-color = "${palette.border}ff";
        background-color = "${palette.surface}ff";
        text-color = "${palette.border}ff";
        font = "VGA 11";
        # The default top layer sits below the minimap's overlay layer, so
        # the minimap would cover the toasts. On overlay they share its
        # layer, and minimap.nix keeps the minimap under them. They also
        # show above fullscreen windows.
        layer = "overlay";
        width = 320;
        margin = "8";
        padding = "8";
        # Auto-dismiss after 5s. Critical alerts are the one exception —
        # 0 means "never auto-dismiss", consistent with red already being
        # reserved here for things that need to be acted on, not glanced at.
        default-timeout = 5000;
        "urgency=critical" = {
          border-color = "${palette.alert}ff";
          text-color = "${palette.alert}ff";
          default-timeout = 0;
        };
      };
    };
    polkit-gnome.enable = true;
    hypridle = {
      enable = true;
      settings = {
        general = {
          # ly-lock reads ly's config, so the lock screen matches the login
          # screen. The NixOS module (programs.ly-lock) installs it.
          lock_cmd = "${osConfig.programs.ly-lock.package}/bin/ly-lock";
          before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
        };
        listener = [
          {
            timeout = 600;
            on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
          }
        ];
      };
    };
  };

  systemd.user.services.power-watcher = {
    Unit = {
      Description = "Charger plug and unplug toasts";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${scripts.powerWatcher}";
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
