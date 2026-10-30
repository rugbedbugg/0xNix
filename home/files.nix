{
  config,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  # Preview pane: text through bat using the terminal's own 16 colours,
  # images as sixel (foot renders it), PDFs as text, archives as a file
  # list, anything else as `file`'s one-line description. lf passes
  # (1) path, (2) width, (3) height in cells.
  previewer = pkgs.writeShellScript "lf-preview" ''
    case "$(${pkgs.file}/bin/file -Lb --mime-type -- "$1")" in
      image/*)
        ${pkgs.chafa}/bin/chafa -f sixel -s "$2x$3" --animate off --polite on -- "$1"
        ;;
      application/pdf)
        ${pkgs.poppler-utils}/bin/pdftotext -l 10 -layout -- "$1" - || true
        ;;
      application/zip | application/x-tar | application/gzip | application/x-xz \
        | application/zstd | application/x-bzip2 | application/x-7z-compressed)
        ${pkgs.libarchive}/bin/bsdtar -tf "$1" || true
        ;;
      text/* | application/json | application/x-shellscript | application/javascript)
        ${pkgs.bat}/bin/bat --color=always --style=plain --paging=never \
          --theme=ansi --terminal-width="$2" -- "$1" || true
        ;;
      *)
        ${pkgs.file}/bin/file -Lb -- "$1"
        ;;
    esac
  '';

  # File dialogs from any app that asks the desktop portal (Chromium,
  # Electron, Firefox) open lf in a floating foot window. The portal passes
  # (1) multiple, (2) directory, (3) save, (4) the suggested path and
  # (5) the file to write the chosen paths to. Opening a file in lf writes
  # it (or every selected file) there and quits. A directory pick takes the
  # directory lf is in when it quits. A save pick opens on the suggested
  # file, which the portal has already created. Full store paths, since the
  # portal service doesn't see the profile's PATH.
  fileChooser = pkgs.writeShellScript "lf-filechooser" ''
    if [ "$2" = 1 ]; then
      set -- -last-dir-path "$5" "$4"
    else
      set -- -selection-path "$5" "$4"
    fi
    exec ${pkgs.foot}/bin/foot --app-id=filechooser ${config.programs.lf.package}/bin/lf "$@"
  '';
in
{
  # lf instead of yazi: lf draws plain single-line box borders (rounded
  # corners are an opt-in borderstyle), uses reverse video for the cursor,
  # has icons off, and shows prompts/errors on the bottom line instead of
  # floating popups. Yazi hardcodes rounded borders on every popup.
  # Unstable for r42, the version these options were checked against.
  programs.lf = {
    enable = true;
    package = pkgs-unstable.lf;
    previewer.source = previewer;
    settings = {
      drawbox = true;
      borderstyle = "box";
      icons = false;
      scrolloff = 4;
      # Every format string, so nothing falls back to lf's default palette.
      # Red only where something went wrong, same rule as the rest of the
      # rice.
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
    keybindings = {
      "." = "set hidden!";
      a = "push %mkdir<space>";
      "<enter>" = "open";
      "<delete>" = "delete";
    };
  };

  # Highest-precedence colour source in lf (above LS_COLORS), so this is
  # the whole listing palette, in exact 24-bit values (38;2;R;G;B) taken
  # from waybar rather than foot's 16-colour defaults:
  #   directories  #ffffff  the white of every border in the rice
  #   files        #9aa0aa  a clear step dimmer — the VGA font has no bold
  #                         weight, and foot's white vs. bright white are
  #                         too close to tell folders from files
  #   symlinks     #5fd7ff  waybar CPU cyan
  #   executables  #7ee787  waybar GPU green
  #   devices/fifo #e5c07b  waybar disk yellow
  #   sockets      #c792ea  waybar RAM purple
  #   broken link  #ff0000  the only red: something is actually wrong
  xdg.configFile."lf/colors".text = ''
    fi 38;2;154;160;170
    di 38;2;255;255;255
    tw 38;2;255;255;255
    ow 38;2;255;255;255
    st 38;2;255;255;255
    ln 38;2;95;215;255
    or 38;2;255;0;0
    ex 38;2;126;231;135
    su 38;2;126;231;135
    sg 38;2;126;231;135
    pi 38;2;229;192;123
    bd 38;2;229;192;123
    cd 38;2;229;192;123
    so 38;2;199;146;234
  '';

  # Backend config for the portal in modules/desktop/portals.nix.
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=${fileChooser}
    default_dir=${config.home.homeDirectory}
    open_mode=suggested
    save_mode=suggested
  '';

  # A fallback for drag-and-drop, not bound to any key.
  home.packages = [ pkgs.thunar ];
}
