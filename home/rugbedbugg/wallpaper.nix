{
  config,
  lib,
  pkgs,
  ...
}:
let
  dir = "${config.xdg.userDirs.pictures}/Wallpapers";
  # The chosen wallpaper is a symlink in state, not a store path: picking
  # one is a runtime action, never a rebuild.
  link = "${config.xdg.stateHome}/wallpaper/current";

  # swaybg decodes through gdk-pixbuf, whose loader set has no WebP (~10 of
  # the wallpapers are WebP, some with a .WEB extension; gdk-pixbuf sniffs
  # content, so the extension doesn't matter). webp-pixbuf-loader's own
  # cache lists only WebP, so concatenate it onto the stock one (PNG and
  # JPEG are built in and need no entry) — the cache format is a plain
  # sequence of entries.
  pixbufLoaders = pkgs.runCommand "wallpaper-pixbuf-loaders.cache" { } ''
    cat ${pkgs.gdk-pixbuf.out}/${pkgs.gdk-pixbuf.moduleDir}.cache \
      ${pkgs.webp-pixbuf-loader}/lib/gdk-pixbuf-2.0/2.10.0/webp-loaders.cache > $out
  '';

  # Long-running owner of the wallpaper. SIGHUP (ExecReload) swaps it
  # without a flash of bare background: the new swaybg starts and maps its
  # surface first, then the old one is killed. Only one swaybg (~a single
  # screen-sized buffer) runs outside that half-second overlap.
  daemon = pkgs.writeShellScript "wallpaper-daemon" ''
    pid=
    start() {
      if [ -e "${link}" ]; then
        ${pkgs.swaybg}/bin/swaybg -m fill -i "$(${pkgs.coreutils}/bin/readlink -f "${link}")" &
      else
        ${pkgs.swaybg}/bin/swaybg -c '#20242c' &
      fi
      new=$!
      ${pkgs.coreutils}/bin/sleep 0.5
      [ -n "$pid" ] && kill "$pid" 2>/dev/null
      pid=$new
    }
    trap 'swapped=1; start' HUP
    trap 'kill "$pid" 2>/dev/null; exit 0' TERM
    start
    # A HUP interrupts `wait` and the trap moves $pid on to the new swaybg.
    # Any other return means swaybg itself died (its status can't tell the
    # two apart: a crash by signal is >128 too), so exit non-zero and let
    # Restart=on-failure take over.
    while :; do
      swapped=0
      wait "$pid"
      [ "$swapped" = 1 ] || exit 1
    done
  '';

  # The switcher UI (wallpaper-switcher.py documents its keys). GTK 3 is
  # already on the system for waybar; the Python process only exists while
  # the switcher is open. wrapGAppsHook3 supplies the GObject typelibs, and
  # the loader cache above gives its previews WebP too.
  switcher = pkgs.stdenv.mkDerivation {
    name = "wallpaper-switcher";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
    ];
    buildInputs = [
      pkgs.gtk3
      (pkgs.python3.withPackages (ps: [ ps.pygobject3 ]))
    ];
    installPhase = ''
      install -Dm755 ${./wallpaper-switcher.py} $out/bin/wallpaper-switcher
    '';
    preFixup = ''
      gappsWrapperArgs+=(--set GDK_PIXBUF_MODULE_FILE ${pixbufLoaders})
    '';
  };

  # wallpaper           open the switcher, or close it if it's open
  # wallpaper set FILE  use FILE
  # wallpaper random    a random one other than the current
  wallpaper = pkgs.writeShellScriptBin "wallpaper" ''
    dir="${dir}"
    link="${link}"

    list() {
      ${pkgs.findutils}/bin/find "$dir" -maxdepth 1 -type f \
          -iregex '.*\.\(jpe?g\|png\|webp?\|gif\|bmp\)' -printf '%f\n' \
        | ${pkgs.coreutils}/bin/sort -f
    }
    current() {
      ${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink "$link" 2>/dev/null)"
    }
    apply() {
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$link")"
      ${pkgs.coreutils}/bin/ln -sfn "$1" "$link"
      ${pkgs.systemd}/bin/systemctl --user reload-or-restart wallpaper.service
    }

    case "$1" in
      set)
        [ -f "$2" ] || { echo "wallpaper: no such file: $2" >&2; exit 1; }
        apply "$(${pkgs.coreutils}/bin/realpath "$2")"
        ;;
      random)
        pick=$(list | ${pkgs.gnugrep}/bin/grep -vxF -- "$(current)" | ${pkgs.coreutils}/bin/shuf -n 1)
        [ -n "$pick" ] && apply "$dir/$pick"
        ;;
      "")
        # The pattern only matches the switcher's own command line (pkill
        # never matches itself), so a second press closes it.
        if ${pkgs.procps}/bin/pkill -f -- "${switcher}/bin/"; then
          exit 0
        fi
        exec ${pkgs.uwsm}/bin/uwsm-app -- ${switcher}/bin/wallpaper-switcher \
          "$dir" "$(${pkgs.coreutils}/bin/readlink "$link" 2>/dev/null)" "$0"
        ;;
      *)
        echo "usage: wallpaper [set FILE | random]" >&2
        exit 2
        ;;
    esac
  '';
in
{
  config = {
    home.packages = [ wallpaper ];

    systemd.user.services.wallpaper = {
      Unit = {
        Description = "Wallpaper (swaybg)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${daemon}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Environment = [ "GDK_PIXBUF_MODULE_FILE=${pixbufLoaders}" ];
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
      -- A small floating switcher at its own natural size (~1000x250);
      -- Hyprland centers new floating windows. Same frame as the special
      -- windows (keybinds.nix).
      hl.window_rule({
        name = "float-style-wallpaper-switcher",
        match = { class = "^wallpaper-switcher$" },
        float = true,
        rounding = 0,
        border_size = 2,
        border_color = "rgba(ffffffee)",
      })
      hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("${wallpaper}/bin/wallpaper"), { description = "Wallpaper switcher" })
    '';
  };
}
