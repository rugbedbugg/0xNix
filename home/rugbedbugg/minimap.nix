{
  config,
  lib,
  pkgs,
  vars,
  palette,
  ...
}:
let
  geometry = import ./overlay-geometry.nix { inherit (vars) screen; };

  # The client script (minimap.py documents its controls), with the
  # palette, the screen size and the tool paths filled in through the
  # @name@ placeholders. The slot positions depend on the minimap's size,
  # which changes while it runs, so the script computes them itself from
  # the screen size and the bar height.
  script = pkgs.replaceVars ./minimap.py {
    inherit (palette)
      border
      outline
      surface
      text
      ;
    screenWidth = toString vars.screen.width;
    screenHeight = toString vars.screen.height;
    bar = toString geometry.bar;
    grim = "${pkgs.grim}/bin/grim";
    hyprctl = "${pkgs.hyprland}/bin/hyprctl";
    state = "${config.xdg.stateHome}/minimap.json";
  };

  # A GTK 3 layer-shell surface. gtk-layer-shell 0.10 does not interpose
  # libwayland, so unlike the GTK 4 version it needs no LD_PRELOAD.
  # wrapGAppsHook3 supplies the GObject typelibs. The process only exists
  # while the minimap is open.
  minimap = pkgs.stdenv.mkDerivation {
    name = "minimap";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.wrapGAppsHook3
      pkgs.gobject-introspection
    ];
    buildInputs = [
      pkgs.gtk3
      pkgs.gtk-layer-shell
      (pkgs.python3.withPackages (ps: [ ps.pygobject3 ]))
    ];
    installPhase = ''
      install -Dm755 ${script} $out/bin/minimap
    '';
  };

  # Track the focused window, or close the minimap if one is open. The
  # pattern only matches the minimap's own command line (pkill never
  # matches itself), so a second press closes it.
  toggle = pkgs.writeShellScript "minimap-toggle" ''
    if ${pkgs.procps}/bin/pkill -f -- "${minimap}/bin/"; then
      exit 0
    fi
    window=$(${pkgs.hyprland}/bin/hyprctl activewindow -j)
    id=$(${pkgs.jq}/bin/jq -r '.stableId // empty' <<< "$window")
    address=$(${pkgs.jq}/bin/jq -r '.address // empty' <<< "$window")
    if [ -z "$id" ] || [ -z "$address" ]; then
      ${pkgs.libnotify}/bin/notify-send -a minimap "Minimap" "No focused window"
      exit 0
    fi
    exec ${pkgs.uwsm}/bin/uwsm-app -- ${minimap}/bin/minimap "$id" "$address"
  '';
in
{
  config = {
    wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
      -- The minimap is a layer-shell surface, so it needs no window rule.
      -- Its namespace is "minimap". It is not hidden from screenshots and
      -- recordings, since it shows what was chosen to be shown. A layer rule
      -- with no_screen_share on that namespace would mask it.
      --
      -- It shares the overlay layer with mako's toasts. There the surface
      -- mapped last draws on top, so a toast already showing when the minimap
      -- opens would end up under it (confirmed live). Hyprland draws a
      -- layer's surfaces in descending order, so 1 keeps the minimap under
      -- every other overlay surface.
      hl.layer_rule({ name = "minimap-below-overlays", match = { namespace = "^minimap$" }, order = 1 })
      hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("${toggle}"), { description = "Minimap of the focused window" })
    '';
  };
}
